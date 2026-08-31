import Foundation
import LectureCore
import LectureServer

final class Runtime: LectureRuntimeControlling, @unchecked Sendable {
    func runtimeSnapshot() throws -> RuntimeSnapshot { RuntimeSnapshot() }
    func startLecture(courseID: String, title: String?) async throws -> LectureRecord { LectureRecord(courseID: courseID, title: title ?? "Class", status: .recording) }
    func stopLecture() async throws -> LectureRecord { LectureRecord(courseID: "c", title: "Class", status: .reviewingEnglish) }
    func addMarker(label: String?) throws -> LectureMarker { LectureMarker(lectureID: "l", time: 0) }
    func retryProcessing(lectureID: String) async throws {}
    func answer(question: String, courseID: String, lectureID: String?) async throws -> ChatMessage { ChatMessage(courseID: courseID, role: .assistant, text: "") }
    func saveDeepSeekKey(_ key: String) async throws {}
    func deleteDeepSeekKey() throws {}
    func testDeepSeek() async throws -> Bool { true }
    func isDeepSeekConfigured() -> Bool { true }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let repository = try SQLiteLectureRepository(databaseURL: URL(fileURLWithPath: ":memory:"))
let server = LoopbackHTTPServer { token in LectureAPIRouter(repository: repository, runtime: Runtime(), token: token, resourcesRoot: root) }
Task {
    _ = try await server.start()
    print(server.browserURL()!.absoluteString)
    fflush(stdout)
}
dispatchMain()
