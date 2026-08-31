@preconcurrency import AVFoundation
import Foundation
import LectureCore
import Speech

@available(macOS 26.0, *)
public enum OfflineDictationTranscriber {
    public static func makeDictationPreset() -> DictationTranscriber.Preset {
        var preset = DictationTranscriber.Preset.timeIndexedLongDictation
        preset.contentHints.insert(.farField)
        preset.transcriptionOptions.insert(.punctuation)
        preset.reportingOptions.remove(.volatileResults)
        preset.reportingOptions.insert(.alternativeTranscriptions)
        preset.attributeOptions.formUnion([
            .audioTimeRange,
            .transcriptionConfidence,
        ])
        return preset
    }

    public static func makeDictationTranscriber(
        locale: Locale = Locale(identifier: "en-US")
    ) -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: makeDictationPreset())
    }

    public static func review(
        audioURL: URL,
        lectureID: String,
        vocabulary: [String],
        locale: Locale = Locale(identifier: "en-US")
    ) async throws -> [TranscriptSegment] {
        let audioFile = try AVAudioFile(forReading: audioURL)
        let transcriber = makeDictationTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .utility, modelRetention: .whileInUse)
        )
        try await analyzer.setContext(
            SpeechAnalysisContextFactory.make(vocabulary: vocabulary)
        )
        try await analyzer.prepareToAnalyze(in: audioFile.processingFormat)

        let resultTask = Task<[TranscriptSegment], Error> {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results where result.isFinal {
                guard let update = TranscriptionSegmentMapper.map(
                    lectureID: lectureID,
                    source: .reviewedEnglish,
                    text: result.text,
                    alternatives: result.alternatives,
                    fallbackRange: result.range,
                    isFinal: true
                ) else { continue }
                segments.append(update.segment)
            }
            return segments
        }

        do {
            let finalTime = try await analyzer.analyzeSequence(from: audioFile)
            if let finalTime {
                try await analyzer.finalizeAndFinish(through: finalTime)
            } else {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            return try await resultTask.value
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }
}
