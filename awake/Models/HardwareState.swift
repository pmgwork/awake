//
//  HardwareState.swift
//  Awake
//

import Foundation

public enum PowerSourceState: Equatable {
    case acPower
    case battery(percentage: Int)

    public var displayName: String {
        switch self {
        case .acPower:
            return L10n.string("AC Power")
        case .battery(let pct):
            return L10n.format("Battery (%d%%)", pct)
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
        }
    }
}

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
}
