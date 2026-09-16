//
//  HardwareState.swift
//  Awake
//

import Foundation

public enum LidState: String, Codable {
    case `open` = "Open"
    case closed = "Closed"
    case unknown = "Unknown"

    public var isClosed: Bool {
        self == .closed
    }

    public var systemImage: String {
        switch self {
        case .open:
            return "laptopcomputer"
        case .closed:
            return "laptopcomputer.and.arrow.down"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

public struct DisplayState: Codable, Equatable {
    public var displayCount: Int
    public var hasExternalDisplay: Bool
    public var isBuiltinDisplayActive: Bool

    public init(displayCount: Int = 1, hasExternalDisplay: Bool = false, isBuiltinDisplayActive: Bool = true) {
        self.displayCount = displayCount
        self.hasExternalDisplay = hasExternalDisplay
        self.isBuiltinDisplayActive = isBuiltinDisplayActive
    }

    public var displayName: String {
        if hasExternalDisplay {
            return L10n.format("External Connected (%d)", displayCount)
        } else if isBuiltinDisplayActive {
            return L10n.string("Internal Only")
        } else {
            return L10n.string("Off / Sleeping")
        }
    }
}

public enum PowerSourceState: Equatable {
    case acPower
    case battery(percentage: Int)
    case unknown

    public var isAC: Bool {
        if case .acPower = self { return true }
        return false
    }

    public var displayName: String {
        switch self {
        case .acPower:
            return L10n.string("AC Power")
        case .battery(let pct):
            return L10n.format("Battery (%d%%)", pct)
        case .unknown:
            return L10n.string("Unknown")
        }
    }

    public var systemImage: String {
        switch self {
        case .acPower:
            return "bolt.fill"
        case .battery(let pct):
            if pct > 75 { return "battery.100" }
            if pct > 50 { return "battery.75" }
            if pct > 25 { return "battery.50" }
            return "battery.25"
        case .unknown:
            return "battery.0"
        }
    }
}

public enum FanMode: String, Codable, CaseIterable, Identifiable {
    case auto = "Auto"
    case maximum = "Maximum"
    case aggressive = "Aggressive"
    case moderate = "Moderate"

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

    public var shortName: String {
        L10n.string(rawValue)
    }
}

public struct ThermalReading: Equatable {
    public var temperatureCelsius: Double?
    public var thermalState: ProcessInfo.ThermalState

    public init(temperatureCelsius: Double? = nil, thermalState: ProcessInfo.ThermalState = .nominal) {
        self.temperatureCelsius = temperatureCelsius
        self.thermalState = thermalState
    }

    public var formattedTemperature: String {
        if let temp = temperatureCelsius {
            return String(format: "%.0f°C", temp)
        } else {
            switch thermalState {
            case .nominal: return L10n.string("Normal")
            case .fair: return L10n.string("Warm")
            case .serious: return L10n.string("Hot")
            case .critical: return L10n.string("Critical")
            @unknown default: return L10n.string("Normal")
            }
        }
    }

    public var stateDescription: String {
        switch thermalState {
        case .nominal: return L10n.string("Nominal")
        case .fair: return L10n.string("Fair")
        case .serious: return L10n.string("Serious")
        case .critical: return L10n.string("Critical")
        @unknown default: return L10n.string("Unknown")
        }
    }
}

public struct FanStatus: Equatable {
    public var mode: FanMode
    public var currentRPM: Int?
    public var maxRPM: Int?
    public var isOverridden: Bool

    public init(mode: FanMode = .auto, currentRPM: Int? = nil, maxRPM: Int? = nil, isOverridden: Bool = false) {
        self.mode = mode
        self.currentRPM = currentRPM
        self.maxRPM = maxRPM
        self.isOverridden = isOverridden
    }

    public var formattedRPM: String {
        if let rpm = currentRPM, rpm > 0 {
            return "\(rpm) RPM"
        }
        return mode.shortName
    }
}

public enum AppExecutionState: String, Codable {
    case idle = "Idle"
    case awakeLidOpen = "Awake / Lid Open"
    case awakeClosedLidCooling = "Awake / Closed-Lid Cooling"
    case normalClamshell = "Awake / Normal Clamshell"

    public var isActive: Bool {
        self != .idle
    }

    public var statusTitle: String {
        switch self {
        case .idle:
            return L10n.string("Idle")
        case .awakeLidOpen:
            return L10n.string("Active (Lid Open)")
        case .awakeClosedLidCooling:
            return L10n.string("Active (Closed-Lid Cooling)")
        case .normalClamshell:
            return L10n.string("Active (Clamshell Desk Mode)")
        }
    }

    public var statusBadgeColorName: String {
        switch self {
        case .idle:
            return "gray"
        case .awakeLidOpen:
            return "green"
        case .awakeClosedLidCooling:
            return "orange"
        case .normalClamshell:
            return "blue"
        }
    }

    public var iconName: String {
        switch self {
        case .idle:
            return "cup.and.saucer"
        case .awakeLidOpen:
            return "cup.and.saucer.fill"
        case .awakeClosedLidCooling:
            return "cup.and.heat.waves.fill"
        case .normalClamshell:
            return "cup.and.saucer.fill"
        }
    }
}
