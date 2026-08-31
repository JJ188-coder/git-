@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import LectureCore
import Speech

@available(macOS 26.0, *)
public final class LiveSpeechTranscriber: @unchecked Sendable {
    public typealias UpdateHandler = @Sendable (TranscriptionUpdate) -> Void
    public typealias ErrorHandler = @Sendable (Error) -> Void

    public enum LiveSpeechError: Error {
        case alreadyRunning
    }

    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let vocabulary: [String]
    private let stateLock = NSLock()
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var errorHandler: ErrorHandler?

    public init(
        vocabulary: [String],
        locale: Locale = Locale(identifier: "en-US")
    ) {
        self.vocabulary = VocabularyNormalizer.normalized(vocabulary)
        transcriber = Self.makeSpeechTranscriber(locale: locale)
        analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
    }

    public static func makeSpeechPreset() -> SpeechTranscriber.Preset {
        var preset = SpeechTranscriber.Preset.timeIndexedProgressiveTranscription
        preset.reportingOptions.formUnion([
            .volatileResults,
            .alternativeTranscriptions,
            .fastResults,
        ])
        preset.attributeOptions.formUnion([
            .audioTimeRange,
            .transcriptionConfidence,
        ])
        return preset
    }

    public static func makeSpeechTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: makeSpeechPreset())
    }

    public static func assetStatus(
        locale: Locale = Locale(identifier: "en-US")
    ) async -> AssetInventory.Status {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .unsupported
        }
        return await AssetInventory.status(
            forModules: [makeSpeechTranscriber(locale: supportedLocale)]
        )
    }

    public static func assetsAvailable(
        locale: Locale = Locale(identifier: "en-US")
    ) async -> Bool {
        await assetStatus(locale: locale) == .installed
    }

    public func start(
        lectureID: String,
        audioFormat: AVAudioFormat,
        handler: @escaping UpdateHandler,
        onError: ErrorHandler? = nil
    ) async throws {
        let isAlreadyRunning = stateLock.withLock { continuation != nil }
        guard !isAlreadyRunning else { throw LiveSpeechError.alreadyRunning }

        try await analyzer.setContext(
            SpeechAnalysisContextFactory.make(vocabulary: vocabulary)
        )
        try await analyzer.prepareToAnalyze(in: audioFormat)

        var inputContinuation: AsyncStream<AnalyzerInput>.Continuation!
        let inputStream = AsyncStream<AnalyzerInput> { inputContinuation = $0 }
        stateLock.withLock {
            continuation = inputContinuation
            errorHandler = onError
        }

        let resultsTask = Task { [transcriber] in
            do {
                for try await result in transcriber.results {
                    guard let update = TranscriptionSegmentMapper.map(
                        lectureID: lectureID,
                        source: .liveEnglish,
                        text: result.text,
                        alternatives: result.alternatives,
                        fallbackRange: result.range,
                        isFinal: result.isFinal
                    ) else { continue }
                    handler(update)
                }
            } catch {
                self.report(error)
            }
        }

        let analysisTask = Task { [analyzer] in
            do {
                let finalTime = try await analyzer.analyzeSequence(inputStream)
                if let finalTime {
                    try await analyzer.finalizeAndFinish(through: finalTime)
                } else {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
            } catch {
                self.report(error)
                await analyzer.cancelAndFinishNow()
            }
        }

        stateLock.withLock {
            self.analysisTask = analysisTask
            self.resultsTask = resultsTask
        }
    }

    public func append(_ buffer: AVAudioPCMBuffer, at time: CMTime? = nil) {
        let inputContinuation = stateLock.withLock { continuation }
        inputContinuation?.yield(AnalyzerInput(buffer: buffer, bufferStartTime: time))
    }

    public func finish() async {
        let tasks = stateLock.withLock { () -> (Task<Void, Never>?, Task<Void, Never>?) in
            continuation?.finish()
            continuation = nil
            return (analysisTask, resultsTask)
        }
        await tasks.0?.value
        await tasks.1?.value
        clearTasks()
    }

    public func cancel() async {
        let tasks = stateLock.withLock { () -> (Task<Void, Never>?, Task<Void, Never>?) in
            continuation?.finish()
            continuation = nil
            analysisTask?.cancel()
            resultsTask?.cancel()
            return (analysisTask, resultsTask)
        }
        await analyzer.cancelAndFinishNow()
        await tasks.0?.value
        await tasks.1?.value
        clearTasks()
    }

    private func report(_ error: Error) {
        stateLock.withLock { errorHandler }?(error)
    }

    private func clearTasks() {
        stateLock.withLock {
            analysisTask = nil
            resultsTask = nil
            errorHandler = nil
        }
    }
}

private extension NSLock {
    func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        lock()
        defer { unlock() }
        return try body()
    }
}
