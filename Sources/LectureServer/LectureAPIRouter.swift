import Foundation
import LectureCore

public protocol LectureRuntimeControlling: Sendable {
    func runtimeSnapshot() throws -> RuntimeSnapshot
    func startLecture(courseID: String, title: String?) async throws -> LectureRecord
    func stopLecture() async throws -> LectureRecord
    func addMarker(label: String?) throws -> LectureMarker
    func retryProcessing(lectureID: String) async throws
    func answer(question: String, courseID: String, lectureID: String?) async throws -> ChatMessage
    func saveDeepSeekKey(_ key: String) async throws
    func deleteDeepSeekKey() throws
    func testDeepSeek() async throws -> Bool
}

public extension LectureRuntimeControlling {
    func reviewedTranscript(lectureID: String) async throws -> [TranscriptSegment] { [] }
}

public struct RuntimeSnapshot: Codable, Sendable {
    public var recording: Bool
    public var activeLectureID: String?
    public var duration: TimeInterval
    public var audioLevel: Double
    public var volatileEnglish: String
    public var volatileChinese: String
    public var speechAvailable: Bool
    public var translationAvailable: Bool
    public var deepSeekConfigured: Bool
    public var statusMessage: String?

    public init(recording: Bool = false, activeLectureID: String? = nil, duration: TimeInterval = 0, audioLevel: Double = 0, volatileEnglish: String = "", volatileChinese: String = "", speechAvailable: Bool = true, translationAvailable: Bool = true, deepSeekConfigured: Bool = false, statusMessage: String? = nil) {
        self.recording = recording
        self.activeLectureID = activeLectureID
        self.duration = duration
        self.audioLevel = audioLevel
        self.volatileEnglish = volatileEnglish
        self.volatileChinese = volatileChinese
        self.speechAvailable = speechAvailable
        self.translationAvailable = translationAvailable
        self.deepSeekConfigured = deepSeekConfigured
        self.statusMessage = statusMessage
    }
}

public final class LectureAPIRouter: @unchecked Sendable {
    private let repository: LectureRepository
    private let runtime: LectureRuntimeControlling
    private let token: String
    private let resourcesRoot: URL

    public init(repository: LectureRepository, runtime: LectureRuntimeControlling, token: String, resourcesRoot: URL) {
        self.repository = repository
        self.runtime = runtime
        self.token = token
        self.resourcesRoot = resourcesRoot
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard isAuthorized(request) else { return .jsonError(status: 401, message: "本地会话已失效，请从 Lecture 菜单重新打开网页") }
        do {
            if request.path.hasPrefix("/api/") { return try await handleAPI(request) }
            return serveStatic(request.path)
        } catch {
            return .jsonError(status: 500, message: userMessage(for: error))
        }
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        if request.query["token"] == token { return true }
        if request.headers["x-lecture-token"] == token { return true }
        if request.headers["authorization"] == "Bearer \(token)" { return true }
        if request.headers["cookie"]?.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }).contains("lecture_token=\(token)") == true { return true }
        return false
    }

    private func handleAPI(_ request: HTTPRequest) async throws -> HTTPResponse {
        let parts = request.path.split(separator: "/").map(String.init)
        switch (request.method, request.path) {
        case ("GET", "/api/health"):
            return .json(["ok": true, "service": true])
        case ("GET", "/api/state"):
            return .json(try runtime.runtimeSnapshot())
        case ("GET", "/api/courses"):
            let query = request.query["q"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .json(query.isEmpty ? try repository.listCourses() : try repository.searchCourses(query: query))
        case ("GET", "/api/lectures"):
            return .json(try repository.allLectures())
        case ("POST", "/api/courses"):
            var course = try decode(Course.self, from: request.body)
            course.updatedAt = Date()
            try repository.upsertCourse(course)
            return .json(course, status: 201)
        case ("POST", "/api/lectures/start"):
            struct Input: Decodable { let courseID: String; let title: String? }
            let input = try decode(Input.self, from: request.body)
            return .json(try await runtime.startLecture(courseID: input.courseID, title: input.title), status: 201)
        case ("POST", "/api/lectures/stop"):
            return .json(try await runtime.stopLecture())
        case ("POST", "/api/markers"):
            struct Input: Decodable { let label: String? }
            let input = request.body.isEmpty ? Input(label: nil) : try decode(Input.self, from: request.body)
            return .json(try runtime.addMarker(label: input.label), status: 201)
        case ("POST", "/api/deepseek/key"):
            struct Input: Decodable { let apiKey: String }
            let input = try decode(Input.self, from: request.body)
            try await runtime.saveDeepSeekKey(input.apiKey)
            return .json(["ok": true])
        case ("DELETE", "/api/deepseek/key"):
            try runtime.deleteDeepSeekKey()
            return .json(["ok": true])
        case ("POST", "/api/deepseek/test"):
            return .json(["ok": try await runtime.testDeepSeek()])
        case ("POST", "/api/qa"):
            struct Input: Decodable { let question: String; let courseID: String; let lectureID: String? }
            let input = try decode(Input.self, from: request.body)
            return .json(try await runtime.answer(question: input.question, courseID: input.courseID, lectureID: input.lectureID), status: 201)
        default:
            break
        }

        if parts.count == 3, parts[0] == "api", parts[1] == "courses" {
            let id = parts[2]
            switch request.method {
            case "GET": return try repository.course(id: id).map { HTTPResponse.json($0) } ?? .jsonError(status: 404, message: "未找到课程")
            case "PUT":
                var course = try decode(Course.self, from: request.body)
                course.id = id; course.updatedAt = Date(); try repository.upsertCourse(course)
                return .json(course)
            case "DELETE":
                if try runtime.runtimeSnapshot().activeLectureID.map({ activeID in
                    try repository.lecture(id: activeID)?.courseID == id
                }) == true {
                    return .jsonError(status: 409, message: "请先结束这门课正在进行的录音")
                }
                let audioPaths = try repository.listLectures(courseID: id).compactMap(\.audioPath)
                try repository.deleteCourse(id: id)
                for path in audioPaths { try? FileManager.default.removeItem(atPath: path) }
                return .json(["ok": true])
            default: break
            }
        }
        if parts.count == 4, parts[0] == "api", parts[1] == "courses", parts[3] == "lectures", request.method == "GET" {
            return .json(try repository.listLectures(courseID: parts[2]))
        }
        if parts.count >= 3, parts[0] == "api", parts[1] == "lectures" {
            let id = parts[2]
            if parts.count == 3, request.method == "GET" {
                guard let lecture = try repository.lecture(id: id) else { return .jsonError(status: 404, message: "未找到课堂") }
                struct Detail: Encodable {
                    let lecture: LectureRecord
                    let transcripts: [TranscriptSegment]
                    let markers: [LectureMarker]
                    let summaries: [SummaryVersion]
                    let liveQuality: TranscriptQuality
                    let reviewedQuality: TranscriptQuality
                }
                let transcripts = try repository.transcripts(lectureID: id, source: nil)
                return .json(Detail(
                    lecture: lecture,
                    transcripts: transcripts,
                    markers: try repository.markers(lectureID: id),
                    summaries: try repository.summaries(lectureID: id),
                    liveQuality: TranscriptQuality(segments: transcripts.filter { $0.source == .liveEnglish }),
                    reviewedQuality: TranscriptQuality(segments: transcripts.filter { $0.source == .reviewedEnglish })
                ))
            }
            if parts.count == 4, parts[3] == "retry", request.method == "POST" {
                try await runtime.retryProcessing(lectureID: id); return .json(["ok": true])
            }
            if parts.count == 4, parts[3] == "audio", request.method == "GET" {
                guard let lecture = try repository.lecture(id: id), let path = lecture.audioPath else { return .jsonError(status: 404, message: "没有录音") }
                let url = URL(fileURLWithPath: path)
                guard let data = try? Data(contentsOf: url) else { return .jsonError(status: 404, message: "录音文件不存在") }
                let mime: String
                switch url.pathExtension.lowercased() {
                case "m4a", "mp4": mime = "audio/mp4"
                case "caf": mime = "audio/x-caf"
                case "wav": mime = "audio/wav"
                default: mime = "application/octet-stream"
                }
                return HTTPResponse(status: 200, headers: ["Content-Type": mime], body: data)
            }
        }
        if parts.count == 4, parts[0] == "api", parts[1] == "courses", parts[3] == "chat", request.method == "GET" {
            return .json(try repository.chatMessages(courseID: parts[2], lectureID: request.query["lectureID"]))
        }
        return .jsonError(status: 404, message: "未找到本地接口")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try LectureJSON.decoder.decode(type, from: data) }
        catch { throw RouterError.invalidBody }
    }

    private func serveStatic(_ path: String) -> HTTPResponse {
        let requested = path == "/" ? "index.html" : String(path.dropFirst())
        guard !requested.contains("..") else { return .jsonError(status: 400, message: "无效路径") }
        let url = resourcesRoot.appendingPathComponent(requested)
        guard let data = try? Data(contentsOf: url), url.path.hasPrefix(resourcesRoot.path) else { return .jsonError(status: 404, message: "页面资源不存在") }
        let mime: String
        switch url.pathExtension.lowercased() {
        case "html": mime = "text/html; charset=utf-8"
        case "css": mime = "text/css; charset=utf-8"
        case "js": mime = "text/javascript; charset=utf-8"
        case "svg": mime = "image/svg+xml"
        default: mime = "application/octet-stream"
        }
        var headers = ["Content-Type": mime, "Cache-Control": "no-store"]
        if path == "/" {
            headers["Set-Cookie"] = "lecture_token=\(token); Path=/; HttpOnly; SameSite=Strict"
            headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; media-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
        }
        return HTTPResponse(status: 200, headers: headers, body: data)
    }

    private func userMessage(for error: Error) -> String {
        if case RouterError.invalidBody = error { return "请求内容不完整" }
        let text = String(describing: error)
        return text.isEmpty ? "本地操作失败" : text
    }
}

private enum RouterError: Error { case invalidBody }
