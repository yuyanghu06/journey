import Foundation
import CoreML
import Accelerate

// MARK: - MiniLMEmbedder
// Loads the all-MiniLM-L6-v2 CoreML model and computes 384-dim sentence embeddings.
//
// Expected files (bundle or Application Support/PersonalityModels/):
//   all-MiniLM-L6-v2.mlpackage   — the CoreML model
//   all-MiniLM-L6-v2-vocab.txt   — WordPiece vocabulary (30 522 lines)
//
// CoreML model I/O contract (standard HuggingFace→coremltools export):
//   input  "input_ids"       : Int32[1, seqLen]
//   input  "attention_mask"  : Int32[1, seqLen]
//   input  "token_type_ids"  : Int32[1, seqLen]  — all zeros for single-sentence input
//   output "sentence_embeddings" | "pooler_output" | "last_hidden_state"
//          → Float32[1, 384] or Float32[1, seqLen, 384] (pooled here if needed)

actor MiniLMEmbedder {

    // MARK: - Constants

    static let modelName  = "all-MiniLM-L6-v2"
    static let vocabName  = "all-MiniLM-L6-v2-vocab.txt"
    static let outputDim  = 384
    static let maxSeqLen  = 128

    // Candidate CoreML output feature names (tried in order)
    private static let outputFeatureNames = ["sentence_embeddings", "pooler_output", "last_hidden_state"]

    // MARK: - State

    private var model: MLModel?
    private(set) var modelURL: URL?          // the URL from which model was loaded
    private var vocab: [String: Int] = [:]   // token → vocab index
    private var resolvedOutputFeatureName: String?  // discovered from model metadata at load time

    /// Human-readable name of the active embedder; set after loadIfNeeded().
    private(set) var activeEmbedderName: String = "not-loaded"

    // MARK: - Init

    init() {}

    // MARK: - Loading

    /// Finds and loads the all-MiniLM-L6-v2 model.  Call once before embed().
    /// Returns true if the CoreML model loaded successfully.
    @discardableResult
    func loadIfNeeded(modelsDirectory: URL) async -> Bool {
        guard model == nil else { return true }

        let candidates = Self.candidateURLs(modelsDirectory: modelsDirectory)
        print("[MiniLMEmbedder] Initialising '\(Self.modelName)' — checking \(candidates.count) location(s)")

        for candidate in candidates {
            print("[MiniLMEmbedder] Trying model path: \(candidate.path)")
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                print("[MiniLMEmbedder] ✗ not found: \(candidate.path)")
                continue
            }

            let loadURL: URL
            if candidate.pathExtension == "mlpackage" {
                do {
                    loadURL = try await MLModel.compileModel(at: candidate)
                    print("[MiniLMEmbedder] Compiled .mlpackage → \(loadURL.lastPathComponent)")
                } catch {
                    print("[MiniLMEmbedder] ✗ compile failed (\(candidate.lastPathComponent)): \(error)")
                    continue
                }
            } else {
                loadURL = candidate
            }

            if let loaded = try? MLModel(contentsOf: loadURL) {
                model    = loaded
                modelURL = candidate
                activeEmbedderName = Self.modelName
                // Discover the actual output feature name from model metadata
                let actualKeys = Array(loaded.modelDescription.outputDescriptionsByName.keys)
                if let matched = Self.outputFeatureNames.first(where: { actualKeys.contains($0) }) {
                    resolvedOutputFeatureName = matched
                } else {
                    resolvedOutputFeatureName = actualKeys.first
                    if let name = resolvedOutputFeatureName {
                        print("[MiniLMEmbedder] ⚠️ no expected output key found; using '\(name)' (actual keys: \(actualKeys))")
                    }
                }
                print("[MiniLMEmbedder] ✅ Loaded embedder: \(Self.modelName) from \(candidate.path)")
                loadVocab(nearModel: candidate, modelsDirectory: modelsDirectory)
                return true
            }
            print("[MiniLMEmbedder] ✗ MLModel init failed: \(candidate.path)")
        }

        print("[MiniLMEmbedder] ⚠️ \(Self.modelName) not available — caller should fall back to NLEmbedding")
        return false
    }

    // MARK: - Embedding

    /// Returns a 384-dim embedding, or nil if the model isn't loaded or inference fails.
    func embed(text: String) -> [Float]? {
        guard let model else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard !vocab.isEmpty else {
            print("[MiniLMEmbedder] ⚠️ vocab not loaded — cannot tokenize for \(Self.modelName)")
            return nil
        }

        let (rawIds, rawMask) = tokenize(trimmed)
        guard !rawIds.isEmpty else { return nil }

        // CoreML model was exported with fixed shape [1, maxSeqLen].
        // Pad with 0s (padding token id=0, mask=0) to fill the fixed length.
        let padLen  = Self.maxSeqLen
        let padId:  Int32 = 0
        let ids  = rawIds  + [Int32](repeating: padId, count: max(0, padLen - rawIds.count))
        let mask = rawMask + [Int32](repeating: 0,     count: max(0, padLen - rawMask.count))

        do {
            let inputIds   = try MLMultiArray(shape: [1, NSNumber(value: padLen)], dataType: .int32)
            let attnMask   = try MLMultiArray(shape: [1, NSNumber(value: padLen)], dataType: .int32)
            let tokenTypes = try MLMultiArray(shape: [1, NSNumber(value: padLen)], dataType: .int32)
            for i in 0..<padLen {
                inputIds[i]   = NSNumber(value: ids[i])
                attnMask[i]   = NSNumber(value: mask[i])
                tokenTypes[i] = 0   // single-sentence: all token type IDs are 0
            }

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids":       inputIds,
                "attention_mask":  attnMask,
                "token_type_ids":  tokenTypes
            ])
            let output = try model.prediction(from: provider)

            // Build candidate list: resolved key (from model metadata) takes priority
            var featureNamesToTry = Self.outputFeatureNames
            if let resolved = resolvedOutputFeatureName, !featureNamesToTry.contains(resolved) {
                featureNamesToTry.insert(resolved, at: 0)
            }

            for featureName in featureNamesToTry {
                guard let arr = output.featureValue(for: featureName)?.multiArrayValue else { continue }
                // The model does mean-pooling internally; pass rawMask for any Swift-side fallback pooling.
                let embedding = poolToVector(arr, seqLen: padLen, mask: rawMask)
                print("[MiniLMEmbedder] embed() → \(Self.modelName) via '\(featureName)': \(embedding.count) dims")
                return embedding
            }

            let actualKeys = output.featureNames
            print("[MiniLMEmbedder] ✗ none of the expected output features found in model response (actual: \(actualKeys))")
        } catch {
            print("[MiniLMEmbedder] ✗ inference error: \(error)")
        }
        return nil
    }

    // MARK: - Private: Model URL candidates

    private static func candidateURLs(modelsDirectory: URL) -> [URL] {
        var urls: [URL] = []
        // 1. Application Support / PersonalityModels (user-downloaded or updated model)
        for ext in ["mlpackage", "mlmodelc"] {
            urls.append(modelsDirectory.appendingPathComponent("\(modelName).\(ext)"))
        }
        // 2. App bundle (shipped with app)
        for ext in ["mlmodelc", "mlpackage"] {
            if let url = Bundle.main.url(forResource: modelName, withExtension: ext) {
                urls.append(url)
            }
        }
        return urls
    }

    // MARK: - Private: Vocab loading

    private func loadVocab(nearModel modelURL: URL, modelsDirectory: URL) {
        let candidates: [URL] = [
            modelURL.deletingLastPathComponent().appendingPathComponent(Self.vocabName),
            modelsDirectory.appendingPathComponent(Self.vocabName),
            Bundle.main.url(forResource: "all-MiniLM-L6-v2-vocab", withExtension: "txt"),
            Bundle.main.url(forResource: "vocab", withExtension: "txt"),
        ].compactMap { $0 }

        for url in candidates {
            print("[MiniLMEmbedder] Trying vocab path: \(url.path)")
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                print("[MiniLMEmbedder] ✗ vocab not found: \(url.path)")
                continue
            }
            var built: [String: Int] = [:]
            content.components(separatedBy: .newlines).enumerated().forEach { idx, line in
                let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty { built[token] = idx }
            }
            vocab = built
            print("[MiniLMEmbedder] ✅ Loaded vocab (\(vocab.count) tokens) from \(url.path)")
            return
        }
        print("[MiniLMEmbedder] ⚠️ vocab file not found — embed() will return nil until vocab is available")
    }

    // MARK: - Private: WordPiece tokenisation (BERT-style)

    private func tokenize(_ text: String) -> (ids: [Int32], mask: [Int32]) {
        guard let clsId  = vocab["[CLS]"],
              let sepId  = vocab["[SEP]"],
              let unkId  = vocab["[UNK]"] else {
            print("[MiniLMEmbedder] ✗ required special tokens [CLS]/[SEP]/[UNK] not in vocab")
            return ([], [])
        }
        let max = Self.maxSeqLen - 2   // reserve [CLS] + [SEP]

        var wordPieces: [Int32] = []
        let lowered = text.lowercased()
        let words   = basicTokenize(lowered)

        outer: for word in words {
            let pieces = wordPieceTokenize(word, unkId: unkId)
            if wordPieces.count + pieces.count > max { break outer }
            wordPieces.append(contentsOf: pieces)
        }

        var ids:  [Int32] = [Int32(clsId)] + wordPieces + [Int32(sepId)]
        var mask: [Int32] = [Int32](repeating: 1, count: ids.count)

        // Pad to maxSeqLen (optional — models often handle variable length, but some need fixed shape)
        // We leave as variable length; the caller passes the actual seqLen.
        return (ids, mask)
    }

    /// Splits on whitespace and punctuation (simplified BERT basic tokenizer).
    private func basicTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in text.unicodeScalars {
            if CharacterSet.whitespaces.contains(ch) {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if CharacterSet.punctuationCharacters.union(.symbols).contains(ch) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else {
                current.unicodeScalars.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Greedy longest-match WordPiece tokenizer.
    private func wordPieceTokenize(_ word: String, unkId: Int) -> [Int32] {
        guard !word.isEmpty else { return [] }

        var subTokens: [Int32] = []
        var start = word.startIndex

        while start < word.endIndex {
            var end   = word.endIndex
            var found = false
            let prefix = start == word.startIndex ? "" : "##"

            while end > start {
                let candidate = prefix + String(word[start..<end])
                if let id = vocab[candidate] {
                    subTokens.append(Int32(id))
                    start = end
                    found = true
                    break
                }
                end = word.index(before: end)
            }
            if !found {
                return [Int32(unkId)]   // whole word → [UNK]
            }
        }
        return subTokens
    }

    // MARK: - Private: Output pooling

    /// Extracts a 1-D Float vector from a CoreML MLMultiArray output.
    /// Handles both [1, 384] (already pooled) and [1, seqLen, 384] (mean-pool here).
    private func poolToVector(_ arr: MLMultiArray, seqLen: Int, mask: [Int32]) -> [Float] {
        let shape = arr.shape.map { $0.intValue }
        switch shape.count {
        case 2 where shape[1] == Self.outputDim:
            // [1, 384] — already sentence embedding
            return (0..<Self.outputDim).map { Float(truncating: arr[$0]) }
        case 3 where shape[2] == Self.outputDim:
            // [1, seqLen, 384] — mean-pool over non-padding tokens
            let s = shape[1]
            var pooled = [Float](repeating: 0, count: Self.outputDim)
            var count: Float = 0
            for t in 0..<s {
                guard t < mask.count, mask[t] == 1 else { continue }
                for d in 0..<Self.outputDim {
                    pooled[d] += Float(truncating: arr[t * Self.outputDim + d])
                }
                count += 1
            }
            if count > 0 { for d in 0..<Self.outputDim { pooled[d] /= count } }
            return pooled
        default:
            // Flatten whatever we got and take first outputDim values
            let flat = (0..<min(arr.count, Self.outputDim)).map { Float(truncating: arr[$0]) }
            return flat
        }
    }
}
