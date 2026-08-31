@preconcurrency import AVFoundation
import Foundation

public final class MicrophoneRecorder: @unchecked Sendable {
    public typealias BufferHandler = @Sendable (AVAudioPCMBuffer) -> Void
    public typealias LevelHandler = @Sendable (AudioLevel) -> Void
    public typealias CheckpointHandler = @Sendable (RecordingCheckpoint) -> Void
    public typealias ErrorHandler = @Sendable (Error) -> Void
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.jiyuanyi.Lecture.Recorder")
    private var file: AVAudioFile?
    private var startedAt: Date?
    private var bufferHandler: BufferHandler?
    private var levelHandler: LevelHandler?
    private var checkpointHandler: CheckpointHandler?
    private var errorHandler: ErrorHandler?
    private var checkpointScheduler = CheckpointScheduler(interval: 5)
    private var outputURL: URL?
    private var sampleRate = 0.0
    private var recordedFrames: Int64 = 0

    public init() {}
    public var isRecording: Bool { engine.isRunning }
    public var duration: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }
    public var inputFormat: AVAudioFormat { engine.inputNode.inputFormat(forBus: 0) }

    public static func protectRecording(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func requestPermission() async -> Bool {
        if #available(macOS 14.0, *) { return await AVAudioApplication.requestRecordPermission() }
        return await withCheckedContinuation { continuation in AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) } }
    }

    public func start(
        url: URL,
        checkpointInterval: TimeInterval = 5,
        onBuffer: @escaping BufferHandler,
        onLevel: @escaping LevelHandler,
        onCheckpoint: CheckpointHandler? = nil,
        onError: ErrorHandler? = nil
    ) throws {
        guard !engine.isRunning else { throw RecorderError.alreadyRecording }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noMicrophone }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try Self.protectRecording(at: url)
        bufferHandler = onBuffer; levelHandler = onLevel
        checkpointHandler = onCheckpoint
        errorHandler = onError
        checkpointScheduler = CheckpointScheduler(interval: checkpointInterval)
        outputURL = url
        sampleRate = format.sampleRate
        recordedFrames = 0
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let copy = Self.copy(buffer)
            self.queue.async {
                do {
                    try self.file?.write(from: copy)
                } catch {
                    self.errorHandler?(error)
                }
                if let channel = copy.floatChannelData?[0] {
                    self.levelHandler?(AudioLevelMeter.measure(interleavedSamples: UnsafeBufferPointer(start: channel, count: Int(copy.frameLength))))
                }
                self.recordedFrames += Int64(copy.frameLength)
                let elapsed = Double(self.recordedFrames) / self.sampleRate
                if self.checkpointScheduler.shouldEmit(elapsedTime: elapsed), let outputURL = self.outputURL {
                    self.checkpointHandler?(RecordingCheckpoint(
                        outputURL: outputURL,
                        elapsedTime: elapsed,
                        recordedFrames: self.recordedFrames
                    ))
                }
                self.bufferHandler?(copy)
            }
        }
        do {
            engine.prepare()
            try engine.start()
            startedAt = Date()
        } catch {
            input.removeTap(onBus: 0)
            queue.sync {
                file = nil
                bufferHandler = nil
                levelHandler = nil
                checkpointHandler = nil
                errorHandler = nil
                outputURL = nil
                sampleRate = 0
                recordedFrames = 0
            }
            throw error
        }
    }

    @discardableResult public func stop() -> TimeInterval {
        let value = duration
        if engine.isRunning { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        queue.sync {
            if let outputURL {
                let recordedDuration = sampleRate > 0
                    ? Double(recordedFrames) / sampleRate
                    : value
                checkpointHandler?(RecordingCheckpoint(
                    outputURL: outputURL,
                    elapsedTime: recordedDuration,
                    recordedFrames: recordedFrames
                ))
            }
            file = nil
            bufferHandler = nil
            levelHandler = nil
            checkpointHandler = nil
            errorHandler = nil
            outputURL = nil
            sampleRate = 0
            recordedFrames = 0
        }
        startedAt = nil
        return value
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let result = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameCapacity)!
        result.frameLength = source.frameLength
        let audioBuffers = UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList)
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        for index in 0..<min(audioBuffers.count, sourceBuffers.count) {
            if let destination = audioBuffers[index].mData, let origin = sourceBuffers[index].mData { memcpy(destination, origin, Int(sourceBuffers[index].mDataByteSize)); audioBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize }
        }
        return result
    }
}

public struct RecordingCheckpoint: Codable, Hashable, Sendable {
    public var outputURL: URL
    public var elapsedTime: TimeInterval
    public var recordedFrames: Int64
    public var createdAt: Date

    public init(
        outputURL: URL,
        elapsedTime: TimeInterval,
        recordedFrames: Int64,
        createdAt: Date = Date()
    ) {
        self.outputURL = outputURL
        self.elapsedTime = elapsedTime
        self.recordedFrames = recordedFrames
        self.createdAt = createdAt
    }
}

public enum RecorderError: Error, CustomStringConvertible {
    case alreadyRecording, noMicrophone
    public var description: String { self == .alreadyRecording ? "已有课堂正在录音" : "没有检测到可用麦克风" }
}
