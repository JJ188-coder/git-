import Foundation

public enum KeyFileImporter {
    public static func importIfPresent(url: URL, into store: DeepSeekKeychainStore = DeepSeekKeychainStore(), fileManager: FileManager = .default) {
        guard ((try? store.loadAPIKey()) ?? nil) == nil, let data = try? Data(contentsOf: url), let value = String(data: data, encoding: .utf8) else { return }
        do {
            try store.saveAPIKey(value)
            try fileManager.removeItem(at: url)
        } catch { }
    }
}
