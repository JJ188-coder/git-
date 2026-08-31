import Foundation

public struct Course: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var code: String?
    public var professor: String
    public var semester: String?
    public var vocabulary: [String]
    public var speechLocaleIdentifier: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        code: String? = nil,
        professor: String,
        semester: String? = nil,
        vocabulary: [String] = [],
        speechLocaleIdentifier: String = "en-US",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.professor = professor
        self.semester = semester
        self.vocabulary = vocabulary
        self.speechLocaleIdentifier = speechLocaleIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, code, professor, semester, vocabulary, speechLocaleIdentifier, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        code = try values.decodeIfPresent(String.self, forKey: .code)
        professor = try values.decodeIfPresent(String.self, forKey: .professor) ?? ""
        semester = try values.decodeIfPresent(String.self, forKey: .semester)
        vocabulary = try values.decodeIfPresent([String].self, forKey: .vocabulary) ?? []
        speechLocaleIdentifier = try values.decodeIfPresent(String.self, forKey: .speechLocaleIdentifier) ?? "en-US"
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

public enum LectureStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case ready
    case recording
    case interrupted
    case reviewingEnglish
    case translatingChinese
    case processingDeepSeek
    case completed
    case failed

    public func canTransition(to next: LectureStatus) -> Bool {
        if self == next { return true }
        switch (self, next) {
        case (.ready, .recording),
             (.recording, .reviewingEnglish),
             (.recording, .interrupted),
             (.recording, .failed),
             (.interrupted, .reviewingEnglish),
             (.interrupted, .recording),
             (.interrupted, .failed),
             (.reviewingEnglish, .translatingChinese),
             (.reviewingEnglish, .processingDeepSeek),
             (.reviewingEnglish, .completed),
             (.reviewingEnglish, .failed),
             (.translatingChinese, .processingDeepSeek),
             (.translatingChinese, .completed),
             (.translatingChinese, .failed),
             (.processingDeepSeek, .processingDeepSeek),
             (.processingDeepSeek, .completed),
             (.processingDeepSeek, .failed),
             (.completed, .processingDeepSeek),
             (.completed, .failed),
             (.failed, .reviewingEnglish),
             (.failed, .failed),
             (.failed, .processingDeepSeek),
             (.failed, .completed):
            return true
        default:
            return false
        }
    }

    public var isIncomplete: Bool {
        self != .completed
    }
}

public struct LectureRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var courseID: String
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var status: LectureStatus
    public var duration: TimeInterval
    public var audioPath: String?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        courseID: String,
        title: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: LectureStatus = .ready,
        duration: TimeInterval = 0,
        audioPath: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.duration = duration
        self.audioPath = audioPath
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum TranscriptSource: String, Codable, CaseIterable, Hashable, Sendable {
    case liveEnglish
    case reviewedEnglish
    case liveChinese
    case correctedChinese
}

public struct TranscriptSegment: Codable, Hashable, Sendable, Identifiable {
    public static let lowConfidenceThreshold = 0.55

    public var id: String
    public var lectureID: String
    public var source: TranscriptSource
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String
    public var confidence: Double?
    public var isFinal: Bool
    public var sourceSegmentID: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        lectureID: String,
        source: TranscriptSource,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        confidence: Double? = nil,
        isFinal: Bool,
        sourceSegmentID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.lectureID = lectureID
        self.source = source
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
        self.isFinal = isFinal
        self.sourceSegmentID = sourceSegmentID
        self.createdAt = createdAt
    }

    public var isLowConfidence: Bool {
        guard let confidence else { return false }
        return confidence < Self.lowConfidenceThreshold
    }
}

public struct TranscriptQuality: Codable, Hashable, Sendable {
    public var segmentCount: Int
    public var scoredSegmentCount: Int
    public var lowConfidenceCount: Int
    public var meanConfidence: Double?

    public init(segments: [TranscriptSegment]) {
        let finalized = segments.filter(\.isFinal)
        let scores = finalized.compactMap { segment -> Double? in
            guard let confidence = segment.confidence, confidence.isFinite, (0...1).contains(confidence) else {
                return nil
            }
            return confidence
        }
        segmentCount = finalized.count
        scoredSegmentCount = scores.count
        lowConfidenceCount = scores.filter { $0 < TranscriptSegment.lowConfidenceThreshold }.count
        meanConfidence = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
    }

    public var lowConfidenceRate: Double? {
        guard scoredSegmentCount > 0 else { return nil }
        return Double(lowConfidenceCount) / Double(scoredSegmentCount)
    }
}

public struct LectureMarker: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var lectureID: String
    public var time: TimeInterval
    public var label: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        lectureID: String,
        time: TimeInterval,
        label: String = "课堂重点",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.lectureID = lectureID
        self.time = time
        self.label = label
        self.createdAt = createdAt
    }
}

public struct GlossaryTerm: Codable, Hashable, Sendable {
    public var english: String
    public var chinese: String
    public var explanation: String

    public init(english: String, chinese: String, explanation: String = "") {
        self.english = english
        self.chinese = chinese
        self.explanation = explanation
    }
}

public struct StudySummary: Codable, Hashable, Sendable {
    public var overview: String
    public var coreConcepts: [String]
    public var definitions: [String]
    public var professorExamples: [String]
    public var professorEmphasis: [String]
    public var possibleExamTopics: [String]
    public var unresolvedQuestions: [String]
    public var glossary: [GlossaryTerm]

    public init(
        overview: String = "",
        coreConcepts: [String] = [],
        definitions: [String] = [],
        professorExamples: [String] = [],
        professorEmphasis: [String] = [],
        possibleExamTopics: [String] = [],
        unresolvedQuestions: [String] = [],
        glossary: [GlossaryTerm] = []
    ) {
        self.overview = overview
        self.coreConcepts = coreConcepts
        self.definitions = definitions
        self.professorExamples = professorExamples
        self.professorEmphasis = professorEmphasis
        self.possibleExamTopics = possibleExamTopics
        self.unresolvedQuestions = unresolvedQuestions
        self.glossary = glossary
    }
}

public struct SummaryVersion: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var lectureID: String
    public var createdAt: Date
    public var content: StudySummary

    public init(
        id: String = UUID().uuidString,
        lectureID: String,
        createdAt: Date = Date(),
        content: StudySummary
    ) {
        self.id = id
        self.lectureID = lectureID
        self.createdAt = createdAt
        self.content = content
    }
}

public struct Citation: Codable, Hashable, Sendable {
    public var lectureID: String
    public var lectureTitle: String
    public var startTime: TimeInterval
    public var segmentID: String?

    public init(lectureID: String, lectureTitle: String, startTime: TimeInterval, segmentID: String? = nil) {
        self.lectureID = lectureID
        self.lectureTitle = lectureTitle
        self.startTime = startTime
        self.segmentID = segmentID
    }
}

public struct ChatMessage: Codable, Hashable, Sendable, Identifiable {
    public enum Role: String, Codable, Hashable, Sendable { case user, assistant }
    public var id: String
    public var courseID: String
    public var lectureID: String?
    public var role: Role
    public var text: String
    public var citations: [Citation]
    public var createdAt: Date

    public init(id: String = UUID().uuidString, courseID: String, lectureID: String? = nil, role: Role, text: String, citations: [Citation] = [], createdAt: Date = Date()) {
        self.id = id
        self.courseID = courseID
        self.lectureID = lectureID
        self.role = role
        self.text = text
        self.citations = citations
        self.createdAt = createdAt
    }
}
