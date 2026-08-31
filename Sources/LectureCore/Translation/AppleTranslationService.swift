import Foundation
import Translation

public protocol LectureTranslationServing: Sendable {
    func isAvailable() async -> Bool
    func translate(_ english: String) async throws -> String
}

@available(macOS 26.4, *)
public actor AppleTranslationService: LectureTranslationServing {
    private let source = Locale.Language(identifier: "en")
    private let target = Locale.Language(identifier: "zh-Hans")
    private var session: TranslationSession?

    public init() {}

    public func isAvailable() async -> Bool {
        let status = await LanguageAvailability(preferredStrategy: .lowLatency).status(from: source, to: target)
        return status == .installed || status == .supported
    }

    public func translate(_ english: String) async throws -> String {
        let text = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let active: TranslationSession
        if let session { active = session }
        else {
            let created = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
            session = created
            active = created
        }
        if !(await active.isReady), active.canRequestDownloads { try await active.prepareTranslation() }
        return try await active.translate(text).targetText
    }
}
