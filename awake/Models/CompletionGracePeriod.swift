import Foundation

/// Tracks inactivity using an absolute deadline so delayed heartbeats do not extend it.
public nonisolated struct CompletionGracePeriod {
    public private(set) var startedAt: Date?

    public mutating func update(isRunning: Bool, now: Date) {
        if isRunning {
            reset()
        } else if startedAt == nil {
            startedAt = now
        }
    }

    public func endDate(duration: TimeInterval) -> Date? {
        startedAt?.addingTimeInterval(max(0, duration))
    }

    public func remainingSeconds(duration: TimeInterval, now: Date) -> Int {
        guard let endDate = endDate(duration: duration) else { return 0 }
        return max(0, Int(ceil(endDate.timeIntervalSince(now))))
    }

    public mutating func reset() {
        startedAt = nil
    }
}
