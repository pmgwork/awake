import Foundation

/// Tracks the transition from running agents to no agents without extending
/// the deadline on subsequent heartbeat ticks. A new run cancels the grace.
struct AgentCompletionGrace {
    private var wasRunning = false
    private var finishedAt: Date?

    mutating func update(running: Bool, duration: TimeInterval, now: Date) -> Date? {
        if running {
            wasRunning = true
            finishedAt = nil
            return nil
        }
        if wasRunning {
            finishedAt = now
            wasRunning = false
        }
        guard let finishedAt, duration.isFinite, duration > 0 else { return nil }
        return finishedAt.addingTimeInterval(duration)
    }
}
