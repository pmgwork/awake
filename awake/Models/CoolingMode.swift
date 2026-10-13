//
//  CoolingMode.swift
//  Awake
//

import Foundation

/// Who decides the fan speed once cooling is started. Everything except
/// `.system` runs the fans at the cooling fan speed.
public enum CoolingMode: String, Codable, CaseIterable, Identifiable {
    case whileAgentRunning
    case timed
    case forced
    case system

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .forced:
            return L10n.string("Forced")
        case .timed:
            return L10n.string("For Duration")
        case .whileAgentRunning:
            return L10n.string("While Agent Is Running")
        case .system:
            return L10n.string("System")
        }
    }

    /// Modes that stay started across a relaunch. Forced and timed cooling
    /// must never leave the fans at 100% unattended.
    public var survivesRelaunch: Bool {
        switch self {
        case .whileAgentRunning: return true
        case .forced, .timed, .system: return false
        }
    }

    /// Conditional modes start as soon as they are selected and are paused
    /// or resumed from the menu instead of being started.
    public var startsOnSelect: Bool {
        self == .whileAgentRunning
    }
}
