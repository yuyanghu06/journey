import Foundation

// MARK: - PersonalityVocabulary
// Loads the token vocabulary from `personality-tokens.json` in the app bundle.
// If the file is missing or malformed, falls back to a minimal hardcoded set.
// To use the full vocabulary: add personality-tokens.json to the Xcode target (Build Phases → Copy Bundle Resources).

enum PersonalityVocabulary {

    static let tokens: [String] = {
        if let url  = Bundle.main.url(forResource: "personality-tokens", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let obj  = try? JSONDecoder().decode([String: [String]].self, from: data),
           let list = obj["tokens"], !list.isEmpty {
            print("[PersonalityVocab] loaded \(list.count) tokens from personality-tokens.json")
            return list
        }
        print("[PersonalityVocab] WARNING: personality-tokens.json not found in bundle — using fallback vocabulary")
        return fallbackTokens
    }()

    // MARK: - Sampling

    /// Returns a random sample of `k` tokens (for bootstrap / fallback inference).
    static func randomSample(k: Int, seed: UInt64? = nil) -> [String] {
        var rng = seed.map { SeededRNG(seed: $0) }
        var indices = Array(0..<tokens.count)
        for i in 0..<min(k, indices.count) {
            let j: Int
            if var r = rng {
                j = i + Int(r.next() % UInt64(indices.count - i))
                rng = r
            } else {
                j = i + Int.random(in: 0...(indices.count - i - 1))
            }
            indices.swapAt(i, j)
        }
        return Array(indices.prefix(k).map { tokens[$0] })
    }

    // MARK: - Fallback (used only when JSON is absent)

    private static let fallbackTokens: [String] = [
        "reflective", "curious", "calm", "energetic", "analytical", "creative",
        "cautious", "optimistic", "introverted", "extroverted", "thoughtful", "spontaneous",
        "anxious", "confident", "warm", "reserved", "imaginative", "practical",
        "emotional", "independent", "systematic", "adaptable", "introspective", "expressive"
    ]
}

// Lightweight seeded PRNG (xorshift64) used for reproducible bootstrap sampling.
private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
