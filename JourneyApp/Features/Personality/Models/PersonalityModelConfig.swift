import Foundation

// MARK: - PersonalityModelConfig
// Controls the size of the on-device personality model.
// Change targetParameterCount to trade off quality vs. storage/speed.

struct PersonalityModelConfig {

    // MARK: - Parameter budget

    /// Target total trainable parameter count (default: 20 million).
    /// The architecture builder picks hidden widths to hit this target.
    var targetParameterCount: Int = 20_000_000

    /// Top-k tokens selected at inference time.
    var topK: Int = 8

    /// Temperature applied to the softmax output before sampling.
    var temperature: Float = 1.0

    /// Fixed vocabulary size (must match PersonalityVocabulary.tokens.count).
    let vocabularySize: Int = PersonalityVocabulary.tokens.count

    /// Input embedding dimension from the active embedder.
    /// all-MiniLM-L6-v2 produces 384-dim; NLEmbedding.sentence produces 512-dim.
    /// Must match the embedder actually in use (MiniLMEmbedder.outputDim when MiniLM is loaded).
    let inputDim: Int = MiniLMEmbedder.outputDim   // 384

    // MARK: - Architecture derivation

    /// Hidden width H chosen to place total params near targetParameterCount.
    ///
    /// Architecture: Dense(1024 → H) + Dense(H → H) + Dense(H → vocabSize)
    /// Params ≈ 1024*H + H + H*H + H + H*vocabSize + vocabSize
    ///        ≈ H^2 + (1024 + vocabSize + 2)*H + vocabSize
    /// Solving the quadratic for H gives the hidden size.
    var hiddenDim: Int {
        // Quadratic: H^2 + (inputDim*2 + vocabSize + 2)*H - targetParameterCount = 0
        let a: Double = 1
        let b: Double = Double(inputDim * 2 + vocabularySize + 2)
        let c: Double = -Double(targetParameterCount)
        let disc = b * b - 4 * a * c
        let h = Int((-b + sqrt(disc)) / (2 * a))
        return max(h, 64)   // floor at 64 to keep the model viable
    }

    // MARK: - Presets

    static let small  = PersonalityModelConfig(targetParameterCount: 5_000_000)
    static let medium = PersonalityModelConfig(targetParameterCount: 20_000_000)
    static let large  = PersonalityModelConfig(targetParameterCount: 50_000_000)
}
