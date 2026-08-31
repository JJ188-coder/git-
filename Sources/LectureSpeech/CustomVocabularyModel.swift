import CryptoKit
import Foundation
import Speech

@available(macOS 26.0, *)
public enum CustomVocabularyModel {
    public enum ModelError: Error, CustomStringConvertible {
        case invalidOutput

        public var description: String {
            switch self {
            case .invalidOutput:
                return "无法生成课程专业词汇模型"
            }
        }
    }

    public static func configuration(
        vocabulary: [String],
        locale: Locale,
        root: URL,
        weight: Double = 0.85
    ) async throws -> SFSpeechLanguageModel.Configuration? {
        let terms = VocabularyNormalizer.normalized(vocabulary)
        guard !terms.isEmpty else { return nil }

        let fingerprint = fingerprint(locale: locale, vocabulary: terms)
        let directory = root.appendingPathComponent(fingerprint, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let trainingURL = directory.appendingPathComponent("training.bin")
        let languageModelURL = directory.appendingPathComponent("language-model.bin")
        let vocabularyURL = directory.appendingPathComponent("vocabulary.bin")
        let configuration = SFSpeechLanguageModel.Configuration(
            languageModel: languageModelURL,
            vocabulary: vocabularyURL,
            weight: NSNumber(value: min(1, max(0, weight)))
        )

        if FileManager.default.fileExists(atPath: languageModelURL.path),
           fileIsUsable(languageModelURL) {
            return configuration
        }

        let data = SFCustomLanguageModelData(
            locale: locale,
            identifier: "com.jiyuanyi.Lecture.course.\(fingerprint)",
            version: "1"
        )
        for term in terms {
            // Give course terms enough weight to survive a noisy, long-dictation review pass.
            data.insert(phraseCount: .init(phrase: term, count: 120))
        }
        try await data.export(to: trainingURL)
        do {
            try await prepare(trainingURL: trainingURL, configuration: configuration)
        } catch {
            try? FileManager.default.removeItem(at: languageModelURL)
            try? FileManager.default.removeItem(at: vocabularyURL)
            throw error
        }

        guard fileIsUsable(languageModelURL) else {
            throw ModelError.invalidOutput
        }
        return configuration
    }

    public static func fingerprint(locale: Locale, vocabulary: [String]) -> String {
        let normalized = VocabularyNormalizer.normalized(vocabulary)
        let source = ([locale.identifier.lowercased()] + normalized.map { $0.lowercased() })
            .joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(source.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func prepare(
        trainingURL: URL,
        configuration: SFSpeechLanguageModel.Configuration
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            SFSpeechLanguageModel.prepareCustomLanguageModel(
                for: trainingURL,
                configuration: configuration
            ) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private static func fileIsUsable(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return false
        }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }
}
