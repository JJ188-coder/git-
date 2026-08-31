import Foundation

public protocol LectureRepository: Sendable {
    func upsertCourse(_ course: Course) throws
    func course(id: String) throws -> Course?
    func listCourses() throws -> [Course]
    func searchCourses(query: String) throws -> [Course]
    func deleteCourse(id: String) throws

    func upsertLecture(_ lecture: LectureRecord) throws
    func lecture(id: String) throws -> LectureRecord?
    func listLectures(courseID: String) throws -> [LectureRecord]
    func incompleteLectures() throws -> [LectureRecord]
    func deleteLecture(id: String) throws

    func appendTranscript(_ segment: TranscriptSegment) throws
    func transcripts(lectureID: String, source: TranscriptSource?) throws -> [TranscriptSegment]
    func appendMarker(_ marker: LectureMarker) throws
    func markers(lectureID: String) throws -> [LectureMarker]
    func appendSummary(_ summary: SummaryVersion) throws
    func summaries(lectureID: String) throws -> [SummaryVersion]
    func appendChatMessage(_ message: ChatMessage) throws
    func chatMessages(courseID: String, lectureID: String?) throws -> [ChatMessage]
}

public final class SQLiteLectureRepository: LectureRepository, @unchecked Sendable {
    private let database: SQLiteDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(databaseURL: URL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
        try migrate()
    }

    private func migrate() throws {
        try database.executeScript("""
        CREATE TABLE IF NOT EXISTS courses (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            code TEXT,
            professor TEXT NOT NULL,
            semester TEXT,
            updated_at REAL NOT NULL,
            payload TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_courses_search ON courses(name, code, professor);

        CREATE TABLE IF NOT EXISTS lectures (
            id TEXT PRIMARY KEY,
            course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            payload TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_lectures_course_started ON lectures(course_id, started_at DESC);
        CREATE INDEX IF NOT EXISTS idx_lectures_status ON lectures(status);

        CREATE TABLE IF NOT EXISTS transcripts (
            id TEXT PRIMARY KEY,
            lecture_id TEXT NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
            source TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            payload TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_transcripts_timeline ON transcripts(lecture_id, source, start_time);

        CREATE TABLE IF NOT EXISTS markers (
            id TEXT PRIMARY KEY,
            lecture_id TEXT NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
            marker_time REAL NOT NULL,
            payload TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_markers_timeline ON markers(lecture_id, marker_time);

        CREATE TABLE IF NOT EXISTS summaries (
            id TEXT PRIMARY KEY,
            lecture_id TEXT NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
            created_at REAL NOT NULL,
            payload TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_summaries_versions ON summaries(lecture_id, created_at DESC);

        CREATE TABLE IF NOT EXISTS chat_messages (
            id TEXT PRIMARY KEY,
            course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            lecture_id TEXT REFERENCES lectures(id) ON DELETE CASCADE,
            created_at REAL NOT NULL,
            payload TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_chat_scope ON chat_messages(course_id, lecture_id, created_at);
        """)
    }

    public func upsertCourse(_ course: Course) throws {
        try database.execute("""
        INSERT INTO courses(id, name, code, professor, semester, updated_at, payload)
        VALUES(?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name=excluded.name, code=excluded.code, professor=excluded.professor,
            semester=excluded.semester, updated_at=excluded.updated_at, payload=excluded.payload
        """, parameters: [
            .text(course.id), .text(course.name), value(course.code), .text(course.professor),
            value(course.semester), .double(course.updatedAt.timeIntervalSince1970), .text(try encode(course))
        ])
    }

    public func course(id: String) throws -> Course? {
        try decodeRows("SELECT payload FROM courses WHERE id = ?", [.text(id)]).first
    }

    public func listCourses() throws -> [Course] {
        try decodeRows("SELECT payload FROM courses ORDER BY updated_at DESC, name COLLATE NOCASE")
    }

    public func searchCourses(query: String) throws -> [Course] {
        let pattern = "%" + query.trimmingCharacters(in: .whitespacesAndNewlines) + "%"
        return try decodeRows("""
        SELECT payload FROM courses
        WHERE name LIKE ? COLLATE NOCASE OR COALESCE(code, '') LIKE ? COLLATE NOCASE OR professor LIKE ? COLLATE NOCASE
        ORDER BY updated_at DESC, name COLLATE NOCASE
        """, [.text(pattern), .text(pattern), .text(pattern)])
    }

    public func deleteCourse(id: String) throws {
        try database.execute("DELETE FROM courses WHERE id = ?", parameters: [.text(id)])
    }

    public func upsertLecture(_ lecture: LectureRecord) throws {
        try database.execute("""
        INSERT INTO lectures(id, course_id, title, status, started_at, updated_at, payload)
        VALUES(?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            course_id=excluded.course_id, title=excluded.title, status=excluded.status,
            started_at=excluded.started_at, updated_at=excluded.updated_at, payload=excluded.payload
        """, parameters: [
            .text(lecture.id), .text(lecture.courseID), .text(lecture.title), .text(lecture.status.rawValue),
            .double(lecture.startedAt.timeIntervalSince1970), .double(lecture.updatedAt.timeIntervalSince1970),
            .text(try encode(lecture))
        ])
    }

    public func lecture(id: String) throws -> LectureRecord? {
        try decodeRows("SELECT payload FROM lectures WHERE id = ?", [.text(id)]).first
    }

    public func listLectures(courseID: String) throws -> [LectureRecord] {
        try decodeRows("SELECT payload FROM lectures WHERE course_id = ? ORDER BY started_at DESC", [.text(courseID)])
    }

    public func incompleteLectures() throws -> [LectureRecord] {
        try decodeRows("SELECT payload FROM lectures WHERE status != ? ORDER BY started_at DESC", [.text(LectureStatus.completed.rawValue)])
    }

    public func deleteLecture(id: String) throws {
        try database.execute("DELETE FROM lectures WHERE id = ?", parameters: [.text(id)])
    }

    public func appendTranscript(_ segment: TranscriptSegment) throws {
        try database.execute("""
        INSERT INTO transcripts(id, lecture_id, source, start_time, end_time, payload)
        VALUES(?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET source=excluded.source, start_time=excluded.start_time,
            end_time=excluded.end_time, payload=excluded.payload
        """, parameters: [
            .text(segment.id), .text(segment.lectureID), .text(segment.source.rawValue),
            .double(segment.startTime), .double(segment.endTime), .text(try encode(segment))
        ])
    }

    public func transcripts(lectureID: String, source: TranscriptSource?) throws -> [TranscriptSegment] {
        if let source {
            return try decodeRows("SELECT payload FROM transcripts WHERE lecture_id = ? AND source = ? ORDER BY start_time", [.text(lectureID), .text(source.rawValue)])
        }
        return try decodeRows("SELECT payload FROM transcripts WHERE lecture_id = ? ORDER BY start_time, source", [.text(lectureID)])
    }

    public func appendMarker(_ marker: LectureMarker) throws {
        try database.execute("""
        INSERT INTO markers(id, lecture_id, marker_time, payload) VALUES(?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET marker_time=excluded.marker_time, payload=excluded.payload
        """, parameters: [.text(marker.id), .text(marker.lectureID), .double(marker.time), .text(try encode(marker))])
    }

    public func markers(lectureID: String) throws -> [LectureMarker] {
        try decodeRows("SELECT payload FROM markers WHERE lecture_id = ? ORDER BY marker_time", [.text(lectureID)])
    }

    public func appendSummary(_ summary: SummaryVersion) throws {
        try database.execute("""
        INSERT INTO summaries(id, lecture_id, created_at, payload) VALUES(?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET created_at=excluded.created_at, payload=excluded.payload
        """, parameters: [.text(summary.id), .text(summary.lectureID), .double(summary.createdAt.timeIntervalSince1970), .text(try encode(summary))])
    }

    public func summaries(lectureID: String) throws -> [SummaryVersion] {
        try decodeRows("SELECT payload FROM summaries WHERE lecture_id = ? ORDER BY created_at DESC", [.text(lectureID)])
    }

    public func appendChatMessage(_ message: ChatMessage) throws {
        try database.execute("""
        INSERT INTO chat_messages(id, course_id, lecture_id, created_at, payload) VALUES(?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET payload=excluded.payload
        """, parameters: [.text(message.id), .text(message.courseID), value(message.lectureID), .double(message.createdAt.timeIntervalSince1970), .text(try encode(message))])
    }

    public func chatMessages(courseID: String, lectureID: String?) throws -> [ChatMessage] {
        if let lectureID {
            return try decodeRows("SELECT payload FROM chat_messages WHERE course_id = ? AND lecture_id = ? ORDER BY created_at", [.text(courseID), .text(lectureID)])
        }
        return try decodeRows("SELECT payload FROM chat_messages WHERE course_id = ? ORDER BY created_at", [.text(courseID)])
    }

    private func value(_ string: String?) -> SQLiteValue {
        string.map(SQLiteValue.text) ?? .null
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SQLiteFailure(operation: "encode", message: "Unable to encode UTF-8 JSON")
        }
        return string
    }

    private func decodeRows<T: Decodable>(_ sql: String, _ parameters: [SQLiteValue] = []) throws -> [T] {
        try database.textRows(sql, parameters: parameters).map { string in
            guard let data = string.data(using: .utf8) else {
                throw SQLiteFailure(operation: "decode", message: "Stored JSON is not UTF-8")
            }
            return try decoder.decode(T.self, from: data)
        }
    }
}
