import CoreMedia
import Foundation
import LectureCore
import LectureSpeech
import Speech

struct LectureSpeechTestFailure: Error, CustomStringConvertible {
    let description: String
}

@discardableResult
private func speechExpect(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String
) throws -> Bool {
    guard try condition() else {
        throw LectureSpeechTestFailure(description: message)
    }
    return true
}

private func speechExpectClose(
    _ actual: Double,
    _ expected: Double,
    accuracy: Double = 0.001,
    _ message: String
) throws {
    try speechExpect(abs(actual - expected) <= accuracy, "\(message): expected \(expected), got \(actual)")
}

private func speechUnwrap<Value>(_ value: Value?, _ message: String) throws -> Value {
    guard let value else {
        throw LectureSpeechTestFailure(description: message)
    }
    return value
}

public func testLectureSpeech() throws {
    try testSegmentMapping()
    try testFallbackMappingAndFinality()
    try testConfidenceClassification()
    try testVocabularyNormalization()
    try testCustomVocabularyFingerprint()
    try testSpeechConfigurations()
    try testLectureEnglishLocaleResolution()
    try testAudioLevels()
    try testCheckpointCadence()
}

@available(macOS 26.0, *)
private func testCustomVocabularyFingerprint() throws {
    let first = CustomVocabularyModel.fingerprint(
        locale: Locale(identifier: "en-US"),
        vocabulary: [" Nash   equilibrium ", "Pareto efficiency"]
    )
    let equivalent = CustomVocabularyModel.fingerprint(
        locale: Locale(identifier: "en-US"),
        vocabulary: ["nash equilibrium", "pareto efficiency"]
    )
    let otherLocale = CustomVocabularyModel.fingerprint(
        locale: Locale(identifier: "en-GB"),
        vocabulary: ["Nash equilibrium", "Pareto efficiency"]
    )
    try speechExpect(first == equivalent, "fingerprint should use normalized case-insensitive terms")
    try speechExpect(first != otherLocale, "fingerprint should separate locale-specific models")
}

@available(macOS 26.0, *)
private func testLectureEnglishLocaleResolution() throws {
    try speechExpect(
        SpeechAssetManager.requestedLocale(identifier: "en-US").identifier == "en-US",
        "US English locale"
    )
    try speechExpect(
        SpeechAssetManager.requestedLocale(identifier: "en-GB").identifier == "en-GB",
        "British English locale"
    )
    try speechExpect(
        SpeechAssetManager.requestedLocale(identifier: "zh-CN").identifier == "en-US",
        "non-English locale should safely fall back to US English"
    )
}

@available(macOS 26.0, *)
private func testSpeechConfigurations() throws {
    let live = LiveSpeechTranscriber.makeSpeechPreset()
    try speechExpect(live.reportingOptions.contains(.volatileResults), "live volatile results")
    try speechExpect(live.reportingOptions.contains(.alternativeTranscriptions), "live alternatives")
    try speechExpect(live.reportingOptions.contains(.fastResults), "live fast results")
    try speechExpect(live.attributeOptions.contains(.audioTimeRange), "live audio time")
    try speechExpect(live.attributeOptions.contains(.transcriptionConfidence), "live confidence")

    let context = SpeechAnalysisContextFactory.make(
        vocabulary: ["  Bayes   rule", "bayes rule", "Nash equilibrium"]
    )
    try speechExpect(
        context.contextualStrings[.general] == ["Bayes rule", "Nash equilibrium"],
        "analysis context vocabulary"
    )

    let review = OfflineDictationTranscriber.makeDictationPreset()
    try speechExpect(review.contentHints.contains(.farField), "review far-field hint")
    try speechExpect(review.attributeOptions.contains(.audioTimeRange), "review audio time")
    try speechExpect(review.attributeOptions.contains(.transcriptionConfidence), "review confidence")
    try speechExpect(!review.reportingOptions.contains(.volatileResults), "review emits final results")
}

private func testSegmentMapping() throws {
    var text = AttributedString("marginal rate")
    let marginalRange = try speechUnwrap(text.range(of: "marginal"), "missing marginal range")
    text[marginalRange].transcriptionConfidence = 0.9
    text[marginalRange].audioTimeRange = speechTimeRange(start: 1.0, duration: 1.25)
    let rateRange = try speechUnwrap(text.range(of: "rate"), "missing rate range")
    text[rateRange].transcriptionConfidence = 0.5
    text[rateRange].audioTimeRange = speechTimeRange(start: 2.5, duration: 1.0)

    let update = try speechUnwrap(
        TranscriptionSegmentMapper.map(
            id: "segment-1",
            lectureID: "lecture-1",
            source: .liveEnglish,
            text: text,
            alternatives: [AttributedString(" marginal ratio "), AttributedString("marginal ratio")],
            fallbackRange: speechTimeRange(start: 20, duration: 5),
            isFinal: false,
            confidenceClassifier: ConfidenceClassifier(lowConfidenceThreshold: 0.75)
        ),
        "non-empty result should map"
    )

    try speechExpect(update.segment.id == "segment-1", "segment id")
    try speechExpect(update.segment.lectureID == "lecture-1", "lecture id")
    try speechExpect(update.segment.source == .liveEnglish, "live source")
    try speechExpect(update.segment.text == "marginal rate", "trimmed text")
    try speechExpect(update.alternatives == ["marginal ratio"], "normalized alternatives")
    try speechExpectClose(update.segment.startTime, 1.0, "mapped start time")
    try speechExpectClose(update.segment.endTime, 3.5, "mapped end time")
    try speechExpectClose(try speechUnwrap(update.segment.confidence, "missing confidence"), 0.7, "mean confidence")
    try speechExpect(update.confidenceClassification == .low, "low confidence classification")
    try speechExpect(update.kind == .draft, "volatile result should be a draft")
    try speechExpect(update.durableSegment == nil, "draft must not be durable")
}

private func testFallbackMappingAndFinality() throws {
    let update = try speechUnwrap(
        TranscriptionSegmentMapper.map(
            id: "segment-2",
            lectureID: "lecture-1",
            source: .reviewedEnglish,
            text: AttributedString("The theorem follows."),
            fallbackRange: speechTimeRange(start: 4.25, duration: 2.5),
            isFinal: true
        ),
        "final result should map"
    )

    try speechExpectClose(update.segment.startTime, 4.25, "fallback start")
    try speechExpectClose(update.segment.endTime, 6.75, "fallback end")
    try speechExpect(update.segment.confidence == nil, "missing confidence stays nil")
    try speechExpect(update.confidenceClassification == .unavailable, "missing confidence classification")
    try speechExpect(update.kind == .final, "final result kind")
    try speechExpect(update.durableSegment == update.segment, "final result is durable")

    let blank = TranscriptionSegmentMapper.map(
        id: "blank",
        lectureID: "lecture-1",
        source: .liveEnglish,
        text: AttributedString("  \n  "),
        fallbackRange: speechTimeRange(start: 0, duration: 1),
        isFinal: true
    )
    try speechExpect(blank == nil, "blank results should be discarded")
}

private func testConfidenceClassification() throws {
    let classifier = ConfidenceClassifier(lowConfidenceThreshold: 0.72)
    try speechExpect(classifier.classify(0.719) == .low, "below threshold")
    try speechExpect(classifier.classify(0.72) == .acceptable, "threshold is acceptable")
    try speechExpect(classifier.classify(0.98) == .acceptable, "high confidence")
    try speechExpect(classifier.classify(nil) == .unavailable, "missing confidence")
    try speechExpect(classifier.classify(-0.01) == .unavailable, "negative confidence")
    try speechExpect(classifier.classify(1.01) == .unavailable, "confidence above one")
    try speechExpect(classifier.classify(.nan) == .unavailable, "NaN confidence")
}

private func testVocabularyNormalization() throws {
    let decomposedCafe = "Cafe\u{301}"
    let result = VocabularyNormalizer.normalized([
        "  Marginal   Rate of\nSubstitution  ",
        "marginal rate of substitution",
        decomposedCafe,
        "Café",
        "  MRS  ",
        "",
    ])

    try speechExpect(
        result == ["Marginal Rate of Substitution", "Café", "MRS"],
        "vocabulary normalization: \(result)"
    )
    try speechExpect(
        VocabularyNormalizer.normalized(["one", "ONE", "two", "three"], maximumCount: 2) == ["one", "two"],
        "maximum count after deduplication"
    )
    try speechExpect(VocabularyNormalizer.normalized(["one"], maximumCount: 0).isEmpty, "zero maximum")
}

private func testAudioLevels() throws {
    let signal = AudioLevelMeter.measure(samples: [0.5, -0.5, 0.5, -0.5])
    try speechExpectClose(signal.rmsDecibels, -6.0206, "signal RMS")
    try speechExpectClose(signal.peakDecibels, -6.0206, "signal peak")
    try speechExpect(signal.normalized > 0.8 && signal.normalized <= 1.0, "normalized signal")

    let silence = AudioLevelMeter.measure(samples: [0, 0, 0])
    try speechExpectClose(silence.rmsDecibels, -96, "silence RMS")
    try speechExpectClose(silence.peakDecibels, -96, "silence peak")
    try speechExpectClose(silence.normalized, 0, "silence normalized")
}

private func testCheckpointCadence() throws {
    var scheduler = CheckpointScheduler(interval: 5)
    try speechExpect(!scheduler.shouldEmit(elapsedTime: 4.99), "before first checkpoint")
    try speechExpect(scheduler.shouldEmit(elapsedTime: 5.0), "first checkpoint")
    try speechExpect(!scheduler.shouldEmit(elapsedTime: 9.99), "before second checkpoint")
    try speechExpect(scheduler.shouldEmit(elapsedTime: 16.0), "catch up after long buffer")
    try speechExpect(!scheduler.shouldEmit(elapsedTime: 19.99), "caught-up boundary")
    try speechExpect(scheduler.shouldEmit(elapsedTime: 20.0), "next checkpoint")

    var disabled = CheckpointScheduler(interval: 0)
    try speechExpect(!disabled.shouldEmit(elapsedTime: 1_000), "non-positive interval disables checkpoints")
}

private func speechTimeRange(start: Double, duration: Double) -> CMTimeRange {
    CMTimeRange(
        start: CMTime(seconds: start, preferredTimescale: 600),
        duration: CMTime(seconds: duration, preferredTimescale: 600)
    )
}
