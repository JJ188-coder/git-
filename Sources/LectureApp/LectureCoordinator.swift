import Foundation
import LectureCore
import LectureServer
import LectureSpeech

@available(macOS 26.4, *)
final class LectureCoordinator: LectureRuntimeControlling, @unchecked Sendable {
    private let repository: LectureRepository
    private let paths: AppPaths
    private let recorder = MicrophoneRecorder()
    private let keychain = DeepSeekKeychainStore()
    private let deepSeek: DeepSeekClient
    private let translation = AppleTranslationService()
    private let lock = NSLock()
    private var activeLecture: LectureRecord?
    private var activeCourse: Course?
    private var speech: LiveSpeechTranscriber?
    private var durationValue: TimeInterval = 0
    private var audioLevelValue: Double = 0
    private var volatileEnglishValue = ""
    private var volatileChineseValue = ""
    private var statusMessageValue: String?

    init(repository: LectureRepository, paths: AppPaths) {
        self.repository = repository; self.paths = paths; deepSeek = DeepSeekClient(keyProvider: keychain)
    }

    private func withState<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }

    func runtimeSnapshot() throws -> RuntimeSnapshot {
        withState { RuntimeSnapshot(recording: recorder.isRecording, activeLectureID: activeLecture?.id, duration: recorder.isRecording ? recorder.duration : durationValue, audioLevel: audioLevelValue, volatileEnglish: volatileEnglishValue, volatileChinese: volatileChineseValue, speechAvailable: true, translationAvailable: true, deepSeekConfigured: (try? keychain.loadAPIKey()) != nil, statusMessage: statusMessageValue) }
    }

    func startLecture(courseID: String, title: String?) async throws -> LectureRecord {
        guard await MicrophoneRecorder.requestPermission() else { throw CoordinatorError.microphoneDenied }
        let alreadyRecording = withState { activeLecture != nil }
        guard !alreadyRecording else { throw CoordinatorError.alreadyRecording }
        guard let course = try repository.course(id: courseID) else { throw CoordinatorError.missingCourse }
        var lecture = LectureRecord(courseID: courseID, title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? defaultTitle(), status: .recording)
        let audioURL = paths.audioURL(lectureID: lecture.id, fileExtension: "caf")
        lecture.audioPath = audioURL.path; try repository.upsertLecture(lecture)
        let liveSpeech = LiveSpeechTranscriber(vocabulary: course.vocabulary)
        withState { activeLecture = lecture; activeCourse = course; speech = liveSpeech; durationValue = 0; volatileEnglishValue = ""; volatileChineseValue = ""; statusMessageValue = "本地录音与英文识别正在运行" }
        try await liveSpeech.start(lectureID: lecture.id, audioFormat: recorder.inputFormat) { [weak self] update in self?.receive(update) }
        do {
            try recorder.start(
                url: audioURL,
                onBuffer: { [weak liveSpeech] buffer in liveSpeech?.append(buffer) },
                onLevel: { [weak self] level in self?.setAudioLevel(level.normalized) },
                onCheckpoint: { [weak self] checkpoint in self?.persistCheckpoint(checkpoint) },
                onError: { [weak self] error in
                    guard let self else { return }
                    self.withState { self.statusMessageValue = "录音写入警告：\(error)" }
                }
            )
        } catch {
            await liveSpeech.cancel(); try? repository.deleteLecture(id: lecture.id); clearActive(); throw error
        }
        return lecture
    }

    func stopLecture() async throws -> LectureRecord {
        let current = withState { (activeLecture, activeCourse, speech) }
        guard var lecture = current.0 else { throw CoordinatorError.notRecording }
        let course = current.1; let liveSpeech = current.2
        let duration = recorder.stop(); await liveSpeech?.finish()
        lecture.duration = duration; lecture.endedAt = Date(); lecture.status = .reviewingEnglish; lecture.updatedAt = Date(); try repository.upsertLecture(lecture)
        withState { durationValue = duration; statusMessageValue = "录音已安全保存，正在本地复核英文" }
        clearActive(keepStatus: true)
        Task { [weak self] in await self?.processAfterClass(lecture: lecture, course: course) }
        return lecture
    }

    func addMarker(label: String?) throws -> LectureMarker {
        let lecture = withState { activeLecture }
        guard let lecture else { throw CoordinatorError.notRecording }
        let marker = LectureMarker(lectureID: lecture.id, time: recorder.duration, label: label?.nonEmpty ?? "课堂重点")
        try repository.appendMarker(marker); return marker
    }

    func retryProcessing(lectureID: String) async throws {
        guard let lecture = try repository.lecture(id: lectureID), let course = try repository.course(id: lecture.courseID) else { throw CoordinatorError.missingLecture }
        await processAfterClass(lecture: lecture, course: course)
    }

    func answer(question: String, courseID: String, lectureID: String?) async throws -> ChatMessage {
        let lectures = try repository.listLectures(courseID: courseID).filter { lectureID == nil || $0.id == lectureID }
        let evidence = try lectures.flatMap { lecture in
            let reviewed = try repository.transcripts(lectureID: lecture.id, source: .reviewedEnglish)
            let source = reviewed.isEmpty ? try repository.transcripts(lectureID: lecture.id, source: .liveEnglish) : reviewed
            return source.filter { $0.text.localizedCaseInsensitiveContains(question.components(separatedBy: .whitespaces).first(where: { $0.count > 2 }) ?? question) }.prefix(20).map { GroundingEvidence(id: $0.id, lectureID: lecture.id, lectureTitle: lecture.title, segmentID: $0.id, startTime: $0.startTime, endTime: $0.endTime, text: $0.text) }
        }
        let user = ChatMessage(courseID: courseID, lectureID: lectureID, role: .user, text: question); try repository.appendChatMessage(user)
        let answer = try await deepSeek.answer(question: question, evidence: evidence)
        let message = ChatMessage(courseID: courseID, lectureID: lectureID, role: .assistant, text: answer.text, citations: answer.citations); try repository.appendChatMessage(message); return message
    }

    func saveDeepSeekKey(_ key: String) async throws { try keychain.saveAPIKey(key); _ = try await deepSeek.testConnection() }
    func deleteDeepSeekKey() throws { try keychain.deleteAPIKey() }
    func testDeepSeek() async throws -> Bool { try await deepSeek.testConnection().isConnected }

    private func receive(_ update: TranscriptionUpdate) {
        if update.kind == .draft { withState { volatileEnglishValue = update.segment.text }; return }
        do { try repository.appendTranscript(update.segment) } catch { withState { statusMessageValue = "字幕保存失败：\(error)" } }
        withState { volatileEnglishValue = "" }
        Task { [weak self] in
            guard let self else { return }
            do {
                let chinese = try await translation.translate(update.segment.text)
                let segment = TranscriptSegment(lectureID: update.segment.lectureID, source: .liveChinese, startTime: update.segment.startTime, endTime: update.segment.endTime, text: chinese, isFinal: true, sourceSegmentID: update.segment.id)
                try repository.appendTranscript(segment); withState { self.volatileChineseValue = chinese }
            } catch { withState { self.statusMessageValue = "英文录音正常；实时翻译暂不可用" } }
        }
    }

    private func processAfterClass(lecture original: LectureRecord, course: Course?) async {
        var lecture = original
        do {
            guard let path = lecture.audioPath else { throw CoordinatorError.missingAudio }
            if lecture.status != .reviewingEnglish { lecture.status = .reviewingEnglish; lecture.updatedAt = Date(); try repository.upsertLecture(lecture) }
            let reviewed = try await OfflineDictationTranscriber.review(audioURL: URL(fileURLWithPath: path), lectureID: lecture.id, vocabulary: course?.vocabulary ?? [])
            for segment in reviewed { try repository.appendTranscript(segment) }
            lecture.status = .processingDeepSeek; lecture.updatedAt = Date(); try repository.upsertLecture(lecture)
            let base = reviewed.isEmpty ? try repository.transcripts(lectureID: lecture.id, source: .liveEnglish) : reviewed
            if (try? keychain.loadAPIKey()) != nil {
                for segment in try await deepSeek.correctTranslation(englishSegments: base, vocabulary: course?.vocabulary ?? []) { try repository.appendTranscript(segment) }
                let summary = try await deepSeek.generateStudySummary(lectureTitle: lecture.title, transcript: base); try repository.appendSummary(.init(lectureID: lecture.id, content: summary))
            }
            lecture.status = .completed; lecture.errorMessage = nil
        } catch { lecture.status = .failed; lecture.errorMessage = SecretRedactor.redact(String(describing: error)) }
        lecture.updatedAt = Date(); try? repository.upsertLecture(lecture)
        withState { statusMessageValue = lecture.status == .completed ? "课后复核与总结已完成" : "课后处理可在历史记录中重试" }
    }

    private func setAudioLevel(_ value: Double) { withState { audioLevelValue = value } }
    private func persistCheckpoint(_ checkpoint: RecordingCheckpoint) {
        guard var lecture = withState({ activeLecture }) else { return }
        lecture.duration = checkpoint.elapsedTime
        lecture.updatedAt = checkpoint.createdAt
        try? repository.upsertLecture(lecture)
    }
    private func clearActive(keepStatus: Bool = false) { withState { activeLecture = nil; activeCourse = nil; speech = nil; audioLevelValue = 0; volatileEnglishValue = ""; volatileChineseValue = ""; if !keepStatus { statusMessageValue = nil } } }
    private func defaultTitle() -> String { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm 课堂"; return formatter.string(from: Date()) }
}

private enum CoordinatorError: Error, CustomStringConvertible {
    case microphoneDenied, alreadyRecording, notRecording, missingCourse, missingLecture, missingAudio
    var description: String {
        switch self { case .microphoneDenied: return "请在系统设置中允许 Lecture 使用麦克风"; case .alreadyRecording: return "已有课堂正在录音"; case .notRecording: return "当前没有正在录音的课堂"; case .missingCourse: return "请先选择课程"; case .missingLecture: return "未找到课堂"; case .missingAudio: return "录音文件不存在" }
    }
}

private extension String { var nonEmpty: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value } }
