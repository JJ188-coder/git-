import Foundation
import LectureCore

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@discardableResult
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws -> Bool {
    guard try condition() else { throw TestFailure(description: message) }
    return true
}

func testDomainModels() throws {
    let course = Course(id: "course-1", name: "Microeconomic Theory", code: "ECON-UA 11", professor: "David Miller", semester: "Fall 2026", vocabulary: ["indifference curve"])
    let lecture = LectureRecord(id: "lecture-1", courseID: course.id, title: "Consumer Choice", status: .completed)
    let segment = TranscriptSegment(id: "segment-1", lectureID: lecture.id, source: .reviewedEnglish, startTime: 12.5, endTime: 18, text: "Marginal rate of substitution", confidence: 0.82, isFinal: true)
    try expect(!(try JSONEncoder().encode(course)).isEmpty, "course should encode")
    try expect(!(try JSONEncoder().encode(lecture)).isEmpty, "lecture should encode")
    try expect(!(try JSONEncoder().encode(segment)).isEmpty, "segment should encode")
    try expect(!segment.isLowConfidence, "0.82 should not be low confidence")
    let low = TranscriptSegment(id: "s", lectureID: "l", source: .liveEnglish, startTime: 0, endTime: 1, text: "uncertain", confidence: 0.54, isFinal: true)
    try expect(low.isLowConfidence, "0.54 should be low confidence")
    try expect(LectureStatus.recording.canTransition(to: .reviewingEnglish), "recording should transition to review")
    try expect(!LectureStatus.completed.canTransition(to: .recording), "completed must not restart")
    let redacted = SecretRedactor.redact("Authorization: Bearer sk-example-secret and api_key=sk-second-secret")
    try expect(!redacted.contains("sk-example-secret") && redacted.contains("[REDACTED]"), "secret redaction")
}

func testStorage() throws {
    func step(_ name: String, _ work: () throws -> Void) throws {
        do { try work() } catch { throw TestFailure(description: "storage step \(name): \(error)") }
    }
    let repository: SQLiteLectureRepository
    do { repository = try SQLiteLectureRepository(databaseURL: URL(fileURLWithPath: ":memory:")) }
    catch { throw TestFailure(description: "storage init: " + String(describing: error)) }
    let course = Course(id: "c1", name: "Statistics II", code: "STAT-UA 202", professor: "Hannah Wilson")
    try step("upsert course") { try repository.upsertCourse(course) }
    var lecture = LectureRecord(id: "l1", courseID: course.id, title: "Regression", status: .recording)
    try step("upsert lecture") { try repository.upsertLecture(lecture) }
    try step("append transcript") { try repository.appendTranscript(TranscriptSegment(id: "s1", lectureID: lecture.id, source: .liveEnglish, startTime: 0, endTime: 3, text: "Consumer preferences", confidence: 0.91, isFinal: true)) }
    try step("append marker") { try repository.appendMarker(LectureMarker(id: "m1", lectureID: lecture.id, time: 1.5, label: "Professor emphasis")) }
    try step("append summary") { try repository.appendSummary(SummaryVersion(id: "sum1", lectureID: lecture.id, createdAt: Date(timeIntervalSince1970: 100), content: StudySummary(overview: "Preferences and utility"))) }
    try expect(try repository.incompleteLectures().map(\.id) == ["l1"], "recover incomplete lecture")
    let searchIDs = try repository.searchCourses(query: "Wilson").map(\.id)
    try expect(searchIDs == ["c1"], "search professor got " + String(describing: searchIDs))
    lecture.status = .completed
    try repository.upsertLecture(lecture)
    try expect(try repository.transcripts(lectureID: "l1", source: .liveEnglish).count == 1, "transcript persisted")
    try expect(try repository.markers(lectureID: "l1").count == 1, "marker persisted")
    try expect(try repository.summaries(lectureID: "l1").count == 1, "summary persisted")
    try repository.deleteCourse(id: "c1")
    try expect(try repository.listLectures(courseID: "c1").isEmpty, "course delete cascades")
}

let tests: [(String, () throws -> Void)] = [
    ("domain", testDomainModels),
    ("storage", testStorage),
]

var failures = 0
for (name, test) in tests {
    do { try test(); print("✓ \(name)") }
    catch { failures += 1; print("✗ \(name): \(error)") }
}
if failures > 0 { exit(1) }
print("All \(tests.count) test groups passed")
