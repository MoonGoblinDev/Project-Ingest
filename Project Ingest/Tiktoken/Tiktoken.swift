import Foundation

public actor Tiktoken {
    public static let shared = Tiktoken()
    private static let cache = NSCache<NSString, Encoding>()

    private init() {}

    public nonisolated func getCachedEncoding(_ name: String) -> Encoding? {
        return Self.cache.object(forKey: name as NSString)
    }

    public func getEncoding(_ name: String) async throws -> Encoding? {
        var name = name

        for ignoredPrefix in Model.IGNORED_PREFIXES where name.hasPrefix(ignoredPrefix) {
            name = String(name.dropFirst(ignoredPrefix.count))
        }

        if let current = Self.cache.object(forKey: name as NSString) {
            return current
        }

        if let encodingName = Model.MODEL_TO_ENCODING[name],
            let existing = getCachedEncoding(encodingName)
        {
            return existing
        }

        guard let vocab = Model.getEncoding(name) else {
            print("Failed to find vocabulary for \(name)")
            return nil
        }
        let encoder = await loadRanks(vocab)
        let regex = try NSRegularExpression(pattern: vocab.pattern)
        let encoding = Encoding(
            name: name, regex: regex, mergeableRanks: encoder, specialTokens: vocab.specialTokens)

        Self.cache.setObject(encoding, forKey: name as NSString)
        return encoding
    }
}

extension Tiktoken {
    fileprivate func loadRanks(_ vocab: Vocab) async -> [[UInt8]: Int] {
        if ["gpt2", "gpt3"].contains(vocab.name) {
            return await Load.dataGymToMergeableBpeRanks(vocabBpeFile: vocab.url)
        } else {
            return await Load.loadTiktokenBpe(url: vocab.url)
        }
    }
}
