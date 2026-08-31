import CoreMedia
import Foundation
import LectureCore
import Speech

public enum TranscriptionUpdateKind: String, Codable, Hashable, Sendable {
    case draft
    case final
}

public struct TranscriptionUpdate: Hashable, Sendable {
    public let segment: TranscriptSegment
    public let alternatives: [String]
    public let confidenceClassification: ConfidenceClassification
    public let kind: TranscriptionUpdateKind

    public init(
        segment: TranscriptSegment,
        alternatives: [String],
        confidenceClassification: ConfidenceClassification,
        kind: TranscriptionUpdateKind
    ) {
        self.segment = segment
        self.alternatives = alternatives
        self.confidenceClassification = confidenceClassification
        self.kind = kind
    }

    public var durableSegment: TranscriptSegment? {
        kind == .final ? segment : nil
    }
}

public enum TranscriptionSegmentMapper {
    public static func map(
        id: String = UUID().uuidString,
        lectureID: String,
        source: TranscriptSource,
        text: AttributedString,
        alternatives: [AttributedString] = [],
        fallbackRange: CMTimeRange,
        isFinal: Bool,
        confidenceClassifier: ConfidenceClassifier = ConfidenceClassifier()
    ) -> TranscriptionUpdate? {
        let plainText = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else { return nil }

        let metrics = attributes(in: text, fallbackRange: fallbackRange)
        let segment = TranscriptSegment(
            id: id,
            lectureID: lectureID,
            source: source,
            startTime: metrics.range.start.seconds,
            endTime: metrics.range.end.seconds,
            text: plainText,
            confidence: metrics.meanConfidence,
            isFinal: isFinal
        )

        return TranscriptionUpdate(
            segment: segment,
            alternatives: normalizedAlternatives(alternatives, excluding: plainText),
            confidenceClassification: confidenceClassifier.classify(metrics.meanConfidence),
            kind: isFinal ? .final : .draft
        )
    }

    private static func attributes(
        in text: AttributedString,
        fallbackRange: CMTimeRange
    ) -> (range: CMTimeRange, meanConfidence: Double?) {
        var earliestStart: Double?
        var latestEnd: Double?
        var confidenceTotal = 0.0
        var confidenceCount = 0

        for run in text.runs {
            if let confidence = run.transcriptionConfidence, confidence.isFinite {
                confidenceTotal += confidence
                confidenceCount += 1
            }

            if let timeRange = run.audioTimeRange,
               timeRange.start.isNumeric,
               timeRange.duration.isNumeric {
                let start = timeRange.start.seconds
                let end = timeRange.end.seconds
                if start.isFinite, end.isFinite, end >= start {
                    earliestStart = min(earliestStart ?? start, start)
                    latestEnd = max(latestEnd ?? end, end)
                }
            }
        }

        let resultRange: CMTimeRange
        if let earliestStart, let latestEnd {
            resultRange = CMTimeRange(
                start: CMTime(seconds: earliestStart, preferredTimescale: 600),
                end: CMTime(seconds: latestEnd, preferredTimescale: 600)
            )
        } else {
            resultRange = fallbackRange
        }

        return (
            range: resultRange,
            meanConfidence: confidenceCount > 0 ? confidenceTotal / Double(confidenceCount) : nil
        )
    }

    private static func normalizedAlternatives(
        _ alternatives: [AttributedString],
        excluding primary: String
    ) -> [String] {
        var seen = Set([primary.lowercased()])
        var result: [String] = []

        for alternative in alternatives {
            let value = String(alternative.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value.lowercased()).inserted else { continue }
            result.append(value)
        }
        return result
    }
}
