import Foundation

public enum VocabularyNormalizer {
    public static func normalized(
        _ vocabulary: [String],
        maximumCount: Int = 500
    ) -> [String] {
        guard maximumCount > 0 else { return [] }

        var seen = Set<String>()
        var result: [String] = []

        for rawTerm in vocabulary {
            let term = rawTerm
                .precomposedStringWithCanonicalMapping
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !term.isEmpty else { continue }

            let deduplicationKey = term.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard seen.insert(deduplicationKey).inserted else { continue }

            result.append(term)
            if result.count == maximumCount { break }
        }

        return result
    }
}
