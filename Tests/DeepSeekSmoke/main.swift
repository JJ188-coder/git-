import Foundation
import LectureCore

Task {
    do {
        let status = try await DeepSeekClient().testConnection()
        print(status.isConnected ? "deepseek-connected" : "deepseek-not-connected")
        exit(status.isConnected ? 0 : 1)
    } catch {
        print(SecretRedactor.redact(String(describing: error)))
        exit(1)
    }
}
dispatchMain()
