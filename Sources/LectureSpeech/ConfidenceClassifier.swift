import Foundation

public enum ConfidenceClassification: String, Codable, Hashable, Sendable {
    case acceptable
    case low
    case unavailable
}

public struct ConfidenceClassifier: Hashable, Sendable {
    public let lowConfidenceThreshold: Double

    public init(lowConfidenceThreshold: Double = 0.55) {
        self.lowConfidenceThreshold = min(max(lowConfidenceThreshold, 0), 1)
    }

    public func classify(_ confidence: Double?) -> ConfidenceClassification {
        guard let confidence, confidence.isFinite, (0...1).contains(confidence) else {
            return .unavailable
        }
        return confidence < lowConfidenceThreshold ? .low : .acceptable
    }
}
