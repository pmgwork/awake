//
//  KeepAwakeMode.swift
//  Awake
//

import Foundation

public enum KeepAwakeModeType: String, Codable, CaseIterable, Identifiable {
    case whileAgentRunning = "whileAgentRunning"
    case indefinitely = "indefinitely"
    case timer = "timer"
    case whileDownloading = "whileDownloading"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .whileAgentRunning:
            return L10n.string("While Agent Is Running")
        case .indefinitely:
            return L10n.string("Indefinitely")
        case .timer:
            return L10n.string("For Duration")
        case .whileDownloading:
            return L10n.string("While Downloading")
        }
    }

}

public struct TimerPreset: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let duration: TimeInterval

    public init(title: String, duration: TimeInterval) {
        self.id = title
        self.title = title
        self.duration = duration
    }

    public static let standardPresets: [TimerPreset] = [
        TimerPreset(title: "15m", duration: 15 * 60),
        TimerPreset(title: "30m", duration: 30 * 60),
        TimerPreset(title: "1h", duration: 60 * 60),
        TimerPreset(title: "2h", duration: 2 * 60 * 60)
    ]
}

/// Independent reasons for preventing sleep; ending one leaves the others active.
struct KeepAwakeActivity {
    let agent: Bool
    let download: Bool
    let active: Bool

    init(manual: Bool, agentEnabled: Bool, agentRunning: Bool, graceActive: Bool,
         downloadEnabled: Bool, downloading: Bool, batteryBlocked: Bool) {
        agent = !batteryBlocked && agentEnabled && (agentRunning || graceActive)
        download = !batteryBlocked && downloadEnabled && downloading
        active = !batteryBlocked && (manual || agent || download)
    }
}
