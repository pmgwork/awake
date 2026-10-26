//
//  HardwareState.swift
//  Awake
//

import Foundation

public enum FanMode: String, Codable, CaseIterable, Identifiable {
    case auto = "Auto"
    case moderate = "Moderate"
    case aggressive = "Aggressive"
    case maximum = "Maximum"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto:
            return L10n.string("Auto (System Control)")
        case .maximum:
            return "100%"
        case .aggressive:
            return "75%"
        case .moderate:
            return "50%"
        }
    }
}
