import Foundation
import LectureSpeech

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: LectureSpeechFileSmoke AUDIO [LOCALE] [VOCABULARY...]\n", stderr)
    exit(64)
}

let audioURL = URL(fileURLWithPath: CommandLine.arguments[1])
let locale = Locale(identifier: CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : "en-US")
let vocabulary = CommandLine.arguments.count >= 4 ? Array(CommandLine.arguments.dropFirst(3)) : []
let root = FileManager.default.temporaryDirectory.appendingPathComponent("LectureSpeechFileSmoke", isDirectory: true)

Task {
    do {
        let segments = try await OfflineDictationTranscriber.review(
            audioURL: audioURL,
            lectureID: "speech-file-smoke",
            vocabulary: vocabulary,
            locale: locale,
            customModelRoot: root
        )
        print("segments=\(segments.count)")
        for segment in segments {
            let confidence = segment.confidence.map { String(format: "%.3f", $0) } ?? "n/a"
            print(String(format: "[%06.2f-%06.2f] [%@] %@", segment.startTime, segment.endTime, confidence, segment.text))
        }
        exit(segments.isEmpty ? 2 : 0)
    } catch {
        fputs("speech-file-smoke-error=\(error)\n", stderr)
        exit(1)
    }
}
dispatchMain()
