import Foundation

public struct CheckpointScheduler: Sendable {
    public let interval: TimeInterval
    private var nextCheckpoint: TimeInterval

    public init(interval: TimeInterval) {
        self.interval = interval
        self.nextCheckpoint = interval
    }

    public mutating func shouldEmit(elapsedTime: TimeInterval) -> Bool {
        guard interval > 0, elapsedTime >= nextCheckpoint else { return false }
        nextCheckpoint = (floor(elapsedTime / interval) + 1) * interval
        return true
    }
}
