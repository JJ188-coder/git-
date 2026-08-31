import Foundation
import SQLite3

public struct SQLiteFailure: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let message: String
    public var description: String { operation + ": " + message }
}

enum SQLiteValue {
    case text(String)
    case double(Double)
    case integer(Int64)
    case null
}

final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        let path = url.lastPathComponent == ":memory:" ? ":memory:" : url.path
        if path != ":memory:" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw SQLiteFailure(operation: "open", message: Self.message(handle))
        }
        try execute("PRAGMA foreign_keys = ON")
        if path != ":memory:" {
            _ = try textRows("PRAGMA journal_mode = WAL")
        }
        _ = try textRows("PRAGMA busy_timeout = 5000")
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String, parameters: [SQLiteValue] = []) throws {
        try locked {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteFailure(operation: "prepare", message: Self.message(handle))
            }
            defer { sqlite3_finalize(statement) }
            try bind(parameters, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteFailure(operation: "execute", message: Self.message(handle))
            }
        }
    }

    func executeScript(_ sql: String) throws {
        try locked {
            var errorPointer: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let message = errorPointer.map { String(cString: $0) } ?? Self.message(handle)
                sqlite3_free(errorPointer)
                throw SQLiteFailure(operation: "migration", message: message)
            }
        }
    }

    func textRows(_ sql: String, parameters: [SQLiteValue] = []) throws -> [String] {
        try locked {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteFailure(operation: "prepare query", message: Self.message(handle))
            }
            defer { sqlite3_finalize(statement) }
            try bind(parameters, to: statement)
            var rows: [String] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else {
                    throw SQLiteFailure(operation: "query", message: Self.message(handle))
                }
                if let value = sqlite3_column_text(statement, 0) {
                    rows.append(String(cString: value))
                }
            }
            return rows
        }
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string):
                result = sqlite3_bind_text(statement, index, string, -1, Self.transient)
            case .double(let number):
                result = sqlite3_bind_double(statement, index, number)
            case .integer(let number):
                result = sqlite3_bind_int64(statement, index, number)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                throw SQLiteFailure(operation: "bind", message: Self.message(handle))
            }
        }
    }

    private func locked<T>(_ work: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    private static func message(_ handle: OpaquePointer?) -> String {
        guard let handle, let value = sqlite3_errmsg(handle) else { return "Unknown SQLite error" }
        return String(cString: value)
    }
}
