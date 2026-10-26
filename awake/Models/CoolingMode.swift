//
//  CoolingMode.swift
//  Awake
//

import Foundation

/// When the fans run at the cooling fan speed once cooling is started.
/// Stopping (or pausing) any mode leaves the fans to the system.
public enum CoolingMode: String, Codable, CaseIterable, Identifiable {
    case whileKeepAwakeIsOn
    case timed
    case forced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .forced:
            return L10n.string("Indefinitely")
        case .timed:
            return L10n.string("For Duration")
        case .whileKeepAwakeIsOn:
            return L10n.string("While Keep Awake Is On")
        }
    }

    /// Modes that stay started across a relaunch. Forced and timed cooling
    /// must never leave the fans at 100% unattended.
    public var survivesRelaunch: Bool {
        switch self {
        case .whileKeepAwakeIsOn: return true
        case .forced, .timed: return false
        }
    }

    /// Conditional modes start as soon as they are selected and are paused
    /// or resumed from the menu instead of being started.
    public var startsOnSelect: Bool {
        self == .whileKeepAwakeIsOn
    }

    /// Automatic cooling runs unattended, so the low-battery cutoff stops it.
    /// Manual cooling was started by the user and keeps running.
    public var stopsAtLowBattery: Bool {
        self == .whileKeepAwakeIsOn
    }
}
