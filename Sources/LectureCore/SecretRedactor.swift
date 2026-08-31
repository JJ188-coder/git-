import Foundation

public enum SecretRedactor {
    private static let patterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"sk-[A-Za-z0-9_-]{8,}"#),
        try! NSRegularExpression(pattern: #"(?i)(authorization\s*:\s*bearer\s+)[^\s]+"#),
        try! NSRegularExpression(pattern: #"(?i)(api[_-]?key\s*[=:]\s*)[^\s&]+"#),
    ]

    public static func redact(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: "$1[REDACTED]")
        }
        return result
    }
}

