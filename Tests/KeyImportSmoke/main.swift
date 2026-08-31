import Foundation
import LectureCore

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let file = root.appendingPathComponent("key")
try Data("sk-test-key-import-123456789".utf8).write(to: file)
let service = "com.jiyuanyi.Lecture.ImportTest." + UUID().uuidString
let store = DeepSeekKeychainStore(service: service)
defer { try? store.deleteAPIKey() }
KeyFileImporter.importIfPresent(url: file, into: store)
guard try store.loadAPIKey() == "sk-test-key-import-123456789", !FileManager.default.fileExists(atPath: file.path) else { exit(1) }
print("key-import-ok")
