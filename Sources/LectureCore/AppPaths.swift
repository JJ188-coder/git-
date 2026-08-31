import Foundation

public struct AppPaths: Sendable {
    public let root: URL
    public let database: URL
    public let recordings: URL
    public let exports: URL
    public let working: URL
    public let speechModels: URL

    public init(root: URL) {
        self.root = root
        self.database = root.appendingPathComponent("lecture.sqlite3")
        self.recordings = root.appendingPathComponent("Recordings", isDirectory: true)
        self.exports = root.appendingPathComponent("Exports", isDirectory: true)
        self.working = root.appendingPathComponent("Working", isDirectory: true)
        self.speechModels = root.appendingPathComponent("SpeechModels", isDirectory: true)
    }

    public static var live: AppPaths {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return AppPaths(root: support.appendingPathComponent("Lecture", isDirectory: true))
    }

    public func createDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: exports, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: working, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: speechModels, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: recordings.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exports.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: working.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: speechModels.path)
    }

    public func audioURL(lectureID: String, fileExtension: String = "m4a") -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safe = lectureID.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : Character("-") }
        let ext = fileExtension.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        return recordings.appendingPathComponent("\(String(safe)).\(ext.isEmpty ? "m4a" : ext)")
    }
}
