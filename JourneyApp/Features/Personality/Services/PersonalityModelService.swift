import Foundation
import Accelerate
import CoreML
import NaturalLanguage

// MARK: - PersonalityModelService
// Actor-based service that owns the on-device personality model lifecycle.
//
// Two-model architecture:
//   • PersonalityModelStock   — full backbone, dual output (latent 512-dim + logits 325-dim).
//                               NOT updatable. Always loaded from bundle.
//   • PersonalityHeadUpdatable — projection head only (Linear 512→325). IS updatable.
//                               Loaded from stored trained version or bundle fallback.
//
// Inference flow:
//   backbone(embedding) → latent → headModel(latent) → logits → top-k tokens
//
// Training flow (MLUpdateTask):
//   For each message: backbone(embedding) → latent (as training input)
//   MLUpdateTask updates headModel weights only — no attention layers in backprop path.
//
// All personality data stays on-device. No model weights are sent to the backend.

actor PersonalityModelService {

    // MARK: - Types

    enum ServiceError: Error {
        case noConversationsAvailable
        case trainingFailed(String)
        case modelStorageError(String)
    }

    // MARK: - State

    private var config: PersonalityModelConfig
    private var manifest: ModelsManifest
    /// Full backbone model (dual output: latent + logits). Always from bundle, never updated.
    private var coreMLModel: MLModel?
    private var coreMLModelURL: URL?
    /// Updatable projection head. Loaded from stored trained version or bundle.
    private var headModel: MLModel?
    private var headModelURL: URL?
    private var randomEngine: RandomWeightEngine?
    private var modelsDirectory: URL
    private var miniLMEmbedder: MiniLMEmbedder = MiniLMEmbedder()

    // MARK: - Init

    init(config: PersonalityModelConfig = .medium) {
        self.config = config
        self.manifest = ModelsManifest(versions: [], currentVersionId: nil)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("PersonalityModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Ensures the best available CoreML model is loaded.
    /// Call this before training so `trainNewVersion` can use MLUpdateTask instead of RandomWeightEngine.
    func ensureModelLoaded() async {
        // Load the MiniLM sentence embedder first (used by all embedding calls).
        let miniLMLoaded = await miniLMEmbedder.loadIfNeeded(modelsDirectory: modelsDirectory)
        if !miniLMLoaded {
            print("[PersonalityModel] ensureModelLoaded() — \(MiniLMEmbedder.modelName) unavailable; NLEmbedding will be used")
        }
        if coreMLModel == nil { await tryLoadCoreMLModel() }
    }

    /// Returns the top-k personality tokens for the current day's messages.
    /// Falls back through inference tiers gracefully.
    func infer(currentDayMessages: [Message]) async throws -> [String] {
        print("[Inference] ═══════════════════════════════════════════")
        print("[Inference] INPUT  — \(currentDayMessages.count) message(s):")
        for (i, m) in currentDayMessages.enumerated() {
            let preview = String(m.text.prefix(80)).replacingOccurrences(of: "\n", with: " ")
            print("[Inference]   [\(i)] \(m.role.rawValue) (\(m.dayKey.rawValue)): \"\(preview)\"")
        }

        let embedding = await computeConversationEmbedding(messages: currentDayMessages)
        if embedding.isEmpty {
            let fallback = PersonalityVocabulary.randomSample(k: config.topK)
            print("[Inference] EMBEDDING — empty (no user text). Using random fallback.")
            print("[Inference] OUTPUT (random): \(fallback)")
            print("[Inference] ═══════════════════════════════════════════")
            return fallback
        }
        let embMin  = embedding.min() ?? 0
        let embMax  = embedding.max() ?? 0
        let embMean = embedding.reduce(0, +) / Float(embedding.count)
        let embNorm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        print("[Inference] EMBEDDING — \(embedding.count) dims | min=\(String(format:"%.4f",embMin)) max=\(String(format:"%.4f",embMax)) mean=\(String(format:"%.4f",embMean)) L2=\(String(format:"%.4f",embNorm))")

        // Try CoreML first
        if coreMLModel == nil { await tryLoadCoreMLModel() }
        if let model = coreMLModel {
            if let tokens = try? inferWithCoreML(model: model, embedding: embedding) {
                print("[Inference] OUTPUT (CoreML): \(tokens)")
                print("[Inference] ═══════════════════════════════════════════")
                return tokens
            }
            print("[Inference] CoreML inference failed — falling back to RandomWeightEngine")
        }

        // Fallback: random-weight engine
        let engine = randomEngine ?? makeRandomEngine()
        if randomEngine == nil { randomEngine = engine }
        let tokens = engine.infer(embedding: embedding, config: config)
        print("[Inference] OUTPUT (RandomWeightEngine): \(tokens)")
        print("[Inference] ═══════════════════════════════════════════")
        return tokens
    }

    /// Attempts to train a new model version from the provided conversations and memories.
    /// Requires a loaded CoreML .mlpackage with updatable layers.
    /// Falls back to updating the randomEngine weights if no CoreML model is present.
    func trainNewVersion(using conversations: [DayConversation], memories: [ContextDocument] = []) async throws -> PersonalityModelVersion {
        print("[PersonalityModel] trainNewVersion() — \(conversations.count) conversations, \(memories.count) memories")
        guard !conversations.isEmpty else { throw ServiceError.noConversationsAvailable }

        // Derive start from the earliest conversation day, fall back to 14 days ago.
        let start = conversations.compactMap { $0.dayKey.date }.min()
            ?? Calendar.current.date(byAdding: .day, value: -13, to: Date())
            ?? Date()
        let end   = Date()

        // Collect only user messages (the model learns the user's voice)
        var userMessages = conversations.flatMap { $0.messages }.filter { $0.role == .user }

        // Inject memories as synthetic user messages so the model internalises personal context.
        let memoryMessages = memories.map { doc in
            Message(id: UUID(), dayKey: .today, role: .user, text: doc.rawText,
                    timestamp: doc.createdAt, status: .delivered)
        }
        userMessages.append(contentsOf: memoryMessages)

        print("[PersonalityModel] trainNewVersion() — \(userMessages.count) user messages to train on (\(memoryMessages.count) from memories)")
        guard !userMessages.isEmpty else { throw ServiceError.noConversationsAvailable }

        // Ensure models are loaded before attempting CoreML training
        if coreMLModel == nil || headModel == nil { await tryLoadCoreMLModel() }

        // Try MLUpdateTask on the HEAD MODEL (no attention layers → no reshape crashes).
        // We need: backbone (coreMLModel) to extract latents, head (headModel) to update.
        if let model = coreMLModel, headModel != nil {
            let outputURL = modelsDirectory.appendingPathComponent(
                "\(DayKey.from(start).rawValue)_\(DayKey.from(end).rawValue).mlpackage"
            )
            do {
                try await runMLUpdateTask(model: model, messages: userMessages, outputURL: outputURL)
                let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                let size  = (attrs?[.size] as? Int64) ?? 0
                let version = PersonalityModelVersion(
                    id: UUID(), periodStart: start, periodEnd: end,
                    createdAt: Date(), fileSizeBytes: size,
                    parameterCount: config.targetParameterCount
                )
                manifest.versions.append(version)
                manifest.currentVersionId = version.id
                saveManifest()
                print("[PersonalityModel] trainNewVersion() → head model saved: \(version.fileName) (\(version.formattedSize))")
                return version
            } catch {
                print("[PersonalityModel] MLUpdateTask failed (\(error.localizedDescription)) — falling back to RandomWeightEngine")
            }
        }

        // Fallback: update random engine weights via reward signal (lightweight)
        print("[PersonalityModel] trainNewVersion() — using RandomWeightEngine (CoreML model not updatable or unavailable)")
        var engine = randomEngine ?? makeRandomEngine()
        await engine.trainOnMessages(userMessages, config: config)
        randomEngine = engine

        // Persist the engine weights as a stand-in version record (no actual .mlpackage)
        let version = PersonalityModelVersion(
            id: UUID(), periodStart: start, periodEnd: end,
            createdAt: Date(), fileSizeBytes: 0,
            parameterCount: config.targetParameterCount
        )
        manifest.versions.append(version)
        manifest.currentVersionId = version.id
        saveManifest()
        print("[PersonalityModel] trainNewVersion() → RandomWeightEngine version recorded: \(version.id)")
        return version
    }

    func loadCurrentModel() -> MLModel? { coreMLModel }

    func listVersions() -> [PersonalityModelVersion] {
        loadManifest()
        return manifest.versions.sorted { $0.createdAt > $1.createdAt }
    }

    func deleteVersion(_ version: PersonalityModelVersion) async throws {
        let fileURL = modelsDirectory.appendingPathComponent(version.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        manifest.versions.removeAll { $0.id == version.id }
        if manifest.currentVersionId == version.id {
            manifest.currentVersionId = manifest.versions.first?.id
        }
        // Stored versions are trained head models — clear head if it matched
        if headModelURL?.lastPathComponent == version.fileName {
            headModel    = nil
            headModelURL = nil
            // Reload bundle head so inference still works
            await loadBundleHeadModel()
        }
        saveManifest()
    }

    func deleteAllVersions() throws {
        for version in manifest.versions {
            let fileURL = modelsDirectory.appendingPathComponent(version.fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        manifest = ModelsManifest(versions: [], currentVersionId: nil)
        saveManifest()
        headModel    = nil
        headModelURL = nil
        randomEngine = nil
    }

    // MARK: - Loading

    private func tryLoadCoreMLModel() async {
        // ── Full backbone model (always from bundle, never updated) ────────────
        let bundleURL: URL? =
            Bundle.main.url(forResource: "PersonalityModelStock", withExtension: "mlmodelc") ??
            Bundle.main.url(forResource: "PersonalityModelStock", withExtension: "mlpackage")

        if let bundleURL {
            let loadURL = await compiledURL(for: bundleURL, label: "backbone")
            if let model = try? MLModel(contentsOf: loadURL) {
                coreMLModel    = model
                coreMLModelURL = loadURL
                print("[PersonalityModel] backbone loaded (\(bundleURL.pathExtension))")
            } else {
                print("[PersonalityModel] backbone found but failed to load: \(bundleURL.lastPathComponent)")
            }
        } else {
            print("[PersonalityModel] no backbone model in bundle — RandomWeightEngine will be used")
        }

        // ── Head model: stored trained version preferred, bundle fallback ──────
        loadManifest()
        if let current = manifest.versions.first(where: { $0.id == manifest.currentVersionId }) {
            let url = modelsDirectory.appendingPathComponent(current.fileName)
            if let model = try? MLModel(contentsOf: url) {
                headModel    = model
                headModelURL = url
                print("[PersonalityModel] trained head loaded: \(current.fileName)")
                return
            }
            // Stale manifest entry — remove it
            manifest = ModelsManifest(versions: manifest.versions.filter { $0.id != current.id },
                                      currentVersionId: nil)
            saveManifest()
            print("[PersonalityModel] stored head model missing: \(current.fileName)")
        }
        await loadBundleHeadModel()
    }

    private func loadBundleHeadModel() async {
        let bundleURL: URL? =
            Bundle.main.url(forResource: Self.headBundleName, withExtension: "mlmodelc") ??
            Bundle.main.url(forResource: Self.headBundleName, withExtension: "mlpackage")
        guard let bundleURL else {
            print("[PersonalityModel] no head model in bundle (checked mlmodelc + mlpackage)")
            return
        }
        let loadURL = await compiledURL(for: bundleURL, label: "head")
        if let model = try? MLModel(contentsOf: loadURL) {
            headModel    = model
            headModelURL = loadURL
            print("[PersonalityModel] bundle head loaded (\(bundleURL.pathExtension))")
        } else {
            print("[PersonalityModel] bundle head found but failed to load: \(bundleURL.lastPathComponent)")
        }
    }

    /// Compiles a .mlpackage to a temp .mlmodelc if needed; returns .mlmodelc path otherwise.
    private func compiledURL(for url: URL, label: String) async -> URL {
        guard url.pathExtension == "mlpackage" else { return url }
        do {
            let compiled = try await MLModel.compileModel(at: url)
            print("[PersonalityModel] compiled \(label) from .mlpackage → \(compiled.lastPathComponent)")
            return compiled
        } catch {
            print("[PersonalityModel] failed to compile \(label): \(error)")
            return url
        }
    }

    // MARK: - CoreML Inference

    // Full backbone model spec:
    //   input  "embedding" — 1536-dim L2-normalised float32 vector
    //   output "latent"    — 512-dim backbone representation
    //   output "logits"    — 325-dim raw logits from stock head
    // Head model spec:
    //   input  "latent"    — 512-dim backbone representation
    //   output "logits"    — 325-dim raw logits (updated weights after training)

    private static let stockModelInputDim  = 1536
    private static let stockModelInputName = "embedding"
    private static let stockModelOutputName = "logits"
    private static let latentOutputName    = "latent"
    private static let headBundleName      = "PersonalityHeadUpdatable"
    private static let headModelInputName  = "latent"
    private static let headModelInputDim   = 512

    private func inferWithCoreML(model: MLModel, embedding: [Float]) throws -> [String] {
        let targetDim = Self.stockModelInputDim

        // Tile embedding to 1536 dims (e.g. 384 → tile ×4), then truncate and L2-normalise.
        var padded = embedding
        while padded.count < targetDim {
            padded.append(contentsOf: embedding.prefix(targetDim - padded.count))
        }
        padded = Array(padded.prefix(targetDim))
        let norm = sqrt(padded.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { padded = padded.map { $0 / norm } }

        print("[Inference] CoreML INPUT — embedding tiled \(embedding.count)→\(padded.count) dims, L2-norm before=\(String(format:"%.4f",norm)) (normalised to 1.0)")

        let multiArray = try MLMultiArray(shape: [1, NSNumber(value: targetDim)], dataType: .float32)
        for (i, v) in padded.enumerated() { multiArray[i] = NSNumber(value: v) }

        let inputProvider  = try MLDictionaryFeatureProvider(dictionary: [Self.stockModelInputName: multiArray])
        let outputProvider = try model.prediction(from: inputProvider)

        // Prefer updated head model (trained weights) over stock logits.
        // headModel takes the 512-dim latent from the backbone and produces fresh logits.
        if let head = headModel,
           let latentArray = outputProvider.featureValue(for: Self.latentOutputName)?.multiArrayValue {
            let latentMin  = (0..<latentArray.count).map { Float(truncating: latentArray[$0]) }.min() ?? 0
            let latentMax  = (0..<latentArray.count).map { Float(truncating: latentArray[$0]) }.max() ?? 0
            print("[Inference] CoreML LATENT — \(latentArray.count) dims | min=\(String(format:"%.4f",latentMin)) max=\(String(format:"%.4f",latentMax)) → routing through trained head model")
            let headInput = try MLDictionaryFeatureProvider(dictionary: [Self.headModelInputName: latentArray])
            let headOutput = try head.prediction(from: headInput)
            if let updatedLogits = headOutput.featureValue(for: Self.stockModelOutputName)?.multiArrayValue {
                var logits = (0..<updatedLogits.count).map { Float(truncating: updatedLogits[$0]) }
                let logMin = logits.min() ?? 0; let logMax = logits.max() ?? 0
                print("[Inference] CoreML LOGITS (head) — \(logits.count) dims | min=\(String(format:"%.4f",logMin)) max=\(String(format:"%.4f",logMax))")
                let tokens = topKTokens(from: &logits, k: config.topK, temperature: config.temperature)
                print("[Inference] CoreML OUTPUT (head) — top-\(config.topK): \(tokens)")
                return tokens
            }
        }

        // Fallback: stock logits from backbone (before any training)
        guard let logitsArray = outputProvider.featureValue(for: Self.stockModelOutputName)?.multiArrayValue else {
            print("[Inference] CoreML OUTPUT — 'logits' feature not found in model response")
            return PersonalityVocabulary.randomSample(k: config.topK)
        }
        var logits = (0..<logitsArray.count).map { Float(truncating: logitsArray[$0]) }
        let logMin = logits.min() ?? 0; let logMax = logits.max() ?? 0
        print("[Inference] CoreML LOGITS (backbone/stock) — \(logits.count) dims | min=\(String(format:"%.4f",logMin)) max=\(String(format:"%.4f",logMax))")
        let tokens = topKTokens(from: &logits, k: config.topK, temperature: config.temperature)
        print("[Inference] CoreML OUTPUT (stock) — top-\(config.topK): \(tokens)")
        return tokens
    }

    // MARK: - MLUpdateTask

    private func runMLUpdateTask(model: MLModel, messages: [Message], outputURL: URL) async throws {
        // MLUpdateTask runs on the HEAD MODEL ONLY (no attention layers → no reshape crashes).
        // For each message we:
        //   1. Run the backbone (full model) to get a 512-dim latent vector.
        //   2. Run inference to get the current top token (used as the training label).
        //   3. Build a batch of (latent, one-hot-label) pairs for the head model.
        guard let sourceURL = headModelURL else {
            throw ServiceError.trainingFailed("No head model URL — cannot run MLUpdateTask")
        }

        var latents: [MLMultiArray] = []
        var labels:  [Int]          = []
        let vocabSize = PersonalityVocabulary.tokens.count

        for message in messages.prefix(50) {
            guard let emb = await embed(text: message.text) else { continue }

            // Prep 1536-dim normalised input for the backbone
            var padded = emb
            while padded.count < Self.stockModelInputDim {
                padded.append(contentsOf: emb.prefix(Self.stockModelInputDim - padded.count))
            }
            padded = Array(padded.prefix(Self.stockModelInputDim))
            let norm = sqrt(padded.reduce(0) { $0 + $1 * $1 })
            if norm > 0 { padded = padded.map { $0 / norm } }

            guard let embArray = try? MLMultiArray(shape: [1, NSNumber(value: padded.count)], dataType: .float32) else { continue }
            for (i, v) in padded.enumerated() { embArray[i] = NSNumber(value: v) }

            // Run backbone → get latent + stock logits
            guard let inputProv = try? MLDictionaryFeatureProvider(dictionary: [Self.stockModelInputName: embArray]),
                  let outProv   = try? await model.prediction(from: inputProv),
                  let latentArr = outProv.featureValue(for: Self.latentOutputName)?.multiArrayValue else { continue }

            // Derive label from current best inference (stock or trained head)
            let tokens = (try? inferWithCoreML(model: model, embedding: emb)) ?? []
            let label  = tokens.first.flatMap { PersonalityVocabulary.tokens.firstIndex(of: $0) } ?? 0

            latents.append(latentArr)
            labels.append(label)
        }

        guard !latents.isEmpty else { throw ServiceError.trainingFailed("No embeddable messages for head training") }
        print("[PersonalityModel] runMLUpdateTask() — \(latents.count) samples, headModel: \(sourceURL.lastPathComponent)")

        // Build MLBatchProvider: latent (512-dim) + one-hot float32 label (325-dim)
        let providers: [MLFeatureProvider] = try latents.enumerated().map { (i, latentArr) in
            let labelArr = try MLMultiArray(shape: [NSNumber(value: vocabSize)], dataType: .float32)
            for k in 0..<vocabSize { labelArr[k] = 0.0 }
            if labels[i] < vocabSize { labelArr[labels[i]] = 1.0 }
            return try MLDictionaryFeatureProvider(dictionary: [
                Self.headModelInputName: latentArr,
                "label": labelArr
            ])
        }
        let batch = MLArrayBatchProvider(array: providers)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                let updateTask = try MLUpdateTask(
                    forModelAt: sourceURL,
                    trainingData: batch,
                    configuration: nil
                ) { [weak self] ctx in
                    if let err = ctx.task.error { cont.resume(throwing: err); return }
                    do {
                        try ctx.model.write(to: outputURL)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                updateTask.resume()
            } catch {
                cont.resume(throwing: error)
            }
        }

        // Reload the updated head model so inference immediately uses new weights
        if let updatedHead = try? MLModel(contentsOf: outputURL) {
            headModel    = updatedHead
            headModelURL = outputURL
            print("[PersonalityModel] head model reloaded from \(outputURL.lastPathComponent)")
        }
    }

    // MARK: - NLEmbedding Helpers

    private func computeConversationEmbedding(messages: [Message]) async -> [Float] {
        let userMessages = messages.filter { $0.role == .user }
        let userText = userMessages.map(\.text).joined(separator: " ")
        print("[Inference] EMBED INPUT — \(userMessages.count) user message(s), combined text length=\(userText.count):")
        for (i, m) in userMessages.enumerated() {
            let preview = String(m.text.prefix(80)).replacingOccurrences(of: "\n", with: " ")
            print("[Inference]   [\(i)] \"\(preview)\"")
        }
        guard var raw = await embed(text: userText) else {
            print("[Inference] EMBED OUTPUT — nil (embedder returned nothing)")
            return []
        }
        // Normalize to config.inputDim: pad with zeros or truncate so downstream is always consistent.
        if raw.count < config.inputDim {
            raw.append(contentsOf: [Float](repeating: 0, count: config.inputDim - raw.count))
        } else if raw.count > config.inputDim {
            raw = Array(raw.prefix(config.inputDim))
        }
        let rawNorm = sqrt(raw.reduce(0) { $0 + $1 * $1 })
        print("[Inference] EMBED OUTPUT — \(raw.count) dims (after pad/truncate to inputDim=\(config.inputDim)), L2=\(String(format:"%.4f",rawNorm))")
        return raw
    }

    func computeReferenceEmbedding(from conversations: [DayConversation], contextDocuments: [ContextDocument] = []) async -> [Float] {
        var allTexts = conversations.flatMap { $0.messages }.filter { $0.role == .user }.map(\.text)
        allTexts += contextDocuments.map(\.rawText)
        guard !allTexts.isEmpty else { return [] }

        var sum   = [Float](repeating: 0, count: config.inputDim)
        var count = 0
        for text in allTexts {
            guard var emb = await embed(text: text) else { continue }
            // Normalize dim before accumulating
            if emb.count < config.inputDim {
                emb.append(contentsOf: [Float](repeating: 0, count: config.inputDim - emb.count))
            } else if emb.count > config.inputDim {
                emb = Array(emb.prefix(config.inputDim))
            }
            for i in 0..<config.inputDim { sum[i] += emb[i] }
            count += 1
        }
        guard count > 0 else { return [] }
        return sum.map { $0 / Float(count) }
    }

    private func embed(text: String) async -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("[PersonalityModel] embed() — skipped (empty text)")
            return nil
        }

        // 1. all-MiniLM-L6-v2 CoreML model (preferred — 384-dim sentence embeddings)
        //    Ensure the embedder is loaded; this is a no-op after the first successful load.
        let miniLMReady = await miniLMEmbedder.loadIfNeeded(modelsDirectory: modelsDirectory)
        let activeName  = await miniLMEmbedder.activeEmbedderName
        let activeURL   = await miniLMEmbedder.modelURL?.path ?? "not loaded"
        print("[PersonalityModel] embed() — active embedder: '\(activeName)', model path: \(activeURL)")

        if miniLMReady, let vector = await miniLMEmbedder.embed(text: trimmed) {
            return vector
        }
        if miniLMReady {
            print("[PersonalityModel] embed() — \(MiniLMEmbedder.modelName) returned nil, falling back to NLEmbedding")
        }

        // 2. Apple NLEmbedding sentence model (fallback)
        if let sentEmbed = NLEmbedding.sentenceEmbedding(for: .english),
           let vector    = sentEmbed.vector(for: trimmed) {
            print("[PersonalityModel] embed() — embedder: NLEmbedding.sentence (\(vector.count) dims)")
            return vector.map { Float($0) }
        }
        print("[PersonalityModel] embed() — NLEmbedding.sentence unavailable, trying word-level averaging")

        // 3. Word embedding average — works on simulator/devices without sentence model
        guard let wordEmbed = NLEmbedding.wordEmbedding(for: .english) else {
            print("[PersonalityModel] embed() — embedder: none (all embedders unavailable)")
            return nil
        }
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = trimmed
        var wordVectors: [[Float]] = []
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex,
                             unit: .word, scheme: .tokenType, options: [.omitWhitespace]) { _, range in
            let token = String(trimmed[range]).lowercased()
            if let vec = wordEmbed.vector(for: token) {
                wordVectors.append(vec.map { Float($0) })
            }
            return true
        }
        guard !wordVectors.isEmpty else {
            print("[PersonalityModel] embed() — no word vectors found for text len=\(trimmed.count)")
            return nil
        }
        let dim = wordVectors[0].count
        var avg = [Float](repeating: 0, count: dim)
        for v in wordVectors { for i in 0..<dim { avg[i] += v[i] } }
        for i in 0..<dim { avg[i] /= Float(wordVectors.count) }
        print("[PersonalityModel] embed() — embedder: NLEmbedding.word avg (\(dim) dims from \(wordVectors.count) words)")
        return avg
    }

    // MARK: - Random-weight engine factory

    private func makeRandomEngine() -> RandomWeightEngine {
        RandomWeightEngine(config: config)
    }

    // MARK: - Top-K sampling

    private func topKTokens(from probs: inout [Float], k: Int, temperature: Float) -> [String] {
        // Apply temperature
        if temperature != 1.0 {
            for i in 0..<probs.count { probs[i] = probs[i] / temperature }
        }
        // Softmax
        let maxVal = probs.max() ?? 0
        var expVals = probs.map { expf($0 - maxVal) }
        let sumExp  = expVals.reduce(0, +)
        for i in 0..<expVals.count { expVals[i] /= sumExp }
        // Top-k indices
        let indexed = expVals.enumerated().sorted { $0.element > $1.element }
        return indexed.prefix(k).compactMap { idx, _ in
            guard idx < PersonalityVocabulary.tokens.count else { return nil }
            return PersonalityVocabulary.tokens[idx]
        }
    }

    // MARK: - Manifest persistence

    private func manifestURL() -> URL {
        modelsDirectory.appendingPathComponent("models_manifest.json")
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL()),
              let m = try? JSONDecoder().decode(ModelsManifest.self, from: data) else { return }
        manifest = m
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL())
    }
}

// MARK: - RandomWeightEngine
// Pure-Swift mini neural net with Accelerate matrix multiply.
// Architecture: Dense(1024 → H) + ReLU + Dense(H → H) + ReLU + Dense(H → 512) + Softmax
// Used for QA and as a fallback when no .mlpackage is present.

struct RandomWeightEngine {

    private var w1: [Float]
    private var w2: [Float]
    private var w3: [Float]
    private let inputDim: Int
    private let hiddenDim: Int
    private let vocabSize: Int

    init(config: PersonalityModelConfig) {
        self.inputDim  = config.inputDim * 2  // concat(conv, history)
        self.hiddenDim = config.hiddenDim
        self.vocabSize = config.vocabularySize

        // Xavier / He initialisation: scale = sqrt(2 / fan_in)
        func randomMatrix(rows: Int, cols: Int) -> [Float] {
            let scale = sqrtf(2.0 / Float(rows))
            return (0..<rows*cols).map { _ in Float.random(in: -scale...scale) }
        }
        w1 = randomMatrix(rows: inputDim,  cols: hiddenDim)
        w2 = randomMatrix(rows: hiddenDim, cols: hiddenDim)
        w3 = randomMatrix(rows: hiddenDim, cols: vocabSize)
    }

    func infer(embedding: [Float], config: PersonalityModelConfig) -> [String] {
        let input = (embedding.count >= config.inputDim) ? Array(embedding.prefix(config.inputDim)) + Array(embedding.prefix(config.inputDim))
                    : embedding + embedding
        guard input.count == inputDim else {
            print("[Inference] RandomWeightEngine — dim mismatch (input=\(input.count) expected=\(inputDim)), using random sample")
            return PersonalityVocabulary.randomSample(k: config.topK)
        }
        let embMin  = input.min() ?? 0; let embMax = input.max() ?? 0
        print("[Inference] RandomWeightEngine INPUT — \(input.count) dims (concat ×2) | min=\(String(format:"%.4f",embMin)) max=\(String(format:"%.4f",embMax)) | hidden=\(hiddenDim) vocab=\(vocabSize)")

        let h1 = relu(matmul(input, w1, m: 1, k: inputDim,  n: hiddenDim))
        let h2 = relu(matmul(h1,    w2, m: 1, k: hiddenDim, n: hiddenDim))
        var logits = matmul(h2, w3, m: 1, k: hiddenDim, n: vocabSize)

        let h1Active = h1.filter { $0 > 0 }.count
        let h2Active = h2.filter { $0 > 0 }.count
        let logMin = logits.min() ?? 0; let logMax = logits.max() ?? 0
        print("[Inference] RandomWeightEngine HIDDEN — h1 active=\(h1Active)/\(hiddenDim) | h2 active=\(h2Active)/\(hiddenDim)")
        print("[Inference] RandomWeightEngine LOGITS — \(logits.count) dims | min=\(String(format:"%.4f",logMin)) max=\(String(format:"%.4f",logMax))")

        let tokens = topKTokens(&logits, k: config.topK)
        print("[Inference] RandomWeightEngine OUTPUT — top-\(config.topK): \(tokens)")
        return tokens
    }

    /// Forward-pass each message embedding and nudge w3 toward top-activated tokens (positive reward signal).
    mutating func trainOnMessages(_ messages: [Message], config: PersonalityModelConfig) async {
        print("[PersonalityModel] RandomWeightEngine.trainOnMessages() — \(messages.count) messages")
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            print("[PersonalityModel] RandomWeightEngine.trainOnMessages() — NLEmbedding unavailable, skipping")
            return
        }
        let lr: Float = 0.01
        for message in messages.prefix(50) {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let vector = embedding.vector(for: trimmed),
                  !vector.isEmpty else { continue }
            let emb = vector.map { Float($0) }
            let half = Array(emb.prefix(config.inputDim))
            let fullInput = half + half
            guard fullInput.count == inputDim else { continue }
            let h1 = relu(matmul(fullInput, w1, m: 1, k: inputDim,  n: hiddenDim))
            let h2 = relu(matmul(h1,        w2, m: 1, k: hiddenDim, n: hiddenDim))
            var logits = matmul(h2,          w3, m: 1, k: hiddenDim, n: vocabSize)
            // Softmax
            let maxLogit = logits.max() ?? 0
            var expVals  = logits.map { expf($0 - maxLogit) }
            let sumExp   = expVals.reduce(0, +)
            guard sumExp > 0 else { continue }
            for i in 0..<expVals.count { expVals[i] /= sumExp }
            // Nudge w3 column of the top-probability token in the direction of h2
            if let topIdx = expVals.enumerated().max(by: { $0.element < $1.element })?.offset {
                for row in 0..<hiddenDim {
                    w3[row * vocabSize + topIdx] += lr * h2[row]
                }
            }
        }
        print("[PersonalityModel] RandomWeightEngine.trainOnMessages() complete")
    }

    // MARK: - Private

    private func matmul(_ a: [Float], _ b: [Float], m: Int, k: Int, n: Int) -> [Float] {
        var c = [Float](repeating: 0, count: m * n)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                    Int32(m), Int32(n), Int32(k),
                    1.0, a, Int32(k), b, Int32(n),
                    0.0, &c, Int32(n))
        return c
    }

    private func relu(_ x: [Float]) -> [Float] {
        x.map { max(0, $0) }
    }

    private func topKTokens(_ logits: inout [Float], k: Int) -> [String] {
        let maxVal = logits.max() ?? 0
        var expVals = logits.map { expf($0 - maxVal) }
        let sumExp  = expVals.reduce(0, +)
        guard sumExp > 0 else { return PersonalityVocabulary.randomSample(k: k) }
        for i in 0..<expVals.count { expVals[i] /= sumExp }
        let indexed = expVals.enumerated().sorted { $0.element > $1.element }
        return indexed.prefix(k).compactMap { idx, _ in
            guard idx < PersonalityVocabulary.tokens.count else { return nil }
            return PersonalityVocabulary.tokens[idx]
        }
    }
}
