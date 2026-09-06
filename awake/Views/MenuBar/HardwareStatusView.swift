//
//  HardwareStatusView.swift
//  Awake
//

import SwiftUI

struct HardwareStatusView: View {
    @ObservedObject var lidMonitor: LidMonitor
    @ObservedObject var displayMonitor: DisplayMonitor
    @ObservedObject var powerMonitor: PowerMonitor
    @ObservedObject var thermalMonitor: ThermalMonitor
    @ObservedObject var fanController: FanController
    @ObservedObject var sleepManager: SleepManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("Mac Status"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 5) {
                statusRow(
                    icon: sleepPreventionIcon,
                    title: "Sleep Prevention",
                    value: sleepManager.health.displayName,
                    valueColor: sleepPreventionColor
                )

                statusRow(
                    icon: displayIcon,
                    title: "Display",
                    value: displayValue,
                    valueColor: displayMonitor.hasExternalDisplay ? .blue : .primary
                )

                statusRow(
                    icon: "fanblades",
                    title: "Fan",
                    value: fanValue,
                    valueColor: fanController.activeMode == .maximum ? .orange : .primary
                )

                statusRow(
                    icon: "thermometer.medium",
                    title: "Temperature",
                    value: thermalMonitor.thermalReading.formattedTemperature,
                    valueColor: temperatureColor
                )

                statusRow(
                    icon: powerMonitor.powerSourceState.systemImage,
                    title: "Power",
                    value: powerMonitor.powerSourceState.displayName,
                    valueColor: powerMonitor.isOnACPower ? .primary : .orange
                )
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let error = sleepManager.lastError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusRow(icon: String, title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 14)

            Text(L10n.string(title))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(valueColor)
        }
    }

    private var displayIcon: String {
        if displayMonitor.hasExternalDisplay {
            return "display.2"
        }
        return "display"
    }

    private var displayValue: String {
        if displayMonitor.hasExternalDisplay {
            return L10n.string("External Connected")
        } else if lidMonitor.isLidClosed {
            return L10n.string("Closed / Sleeping")
        } else {
            return L10n.string("Internal")
        }
    }

    private var fanValue: String {
        if fanController.activeMode == .maximum {
            return L10n.string("Maximum")
        } else if fanController.activeMode == .aggressive {
            return L10n.string("Aggressive")
        } else {
            return L10n.string("Auto")
        }
    }

    private var temperatureColor: Color {
        switch thermalMonitor.thermalReading.thermalState {
        case .nominal: return .primary
        case .fair: return .orange
        case .serious: return .red
        case .critical: return .purple
        @unknown default: return .primary
        }
    }

    private var sleepPreventionIcon: String {
        switch sleepManager.health {
        case .inactive: return "moon.zzz"
        case .active: return "checkmark.shield.fill"
        case .degraded: return "exclamationmark.shield.fill"
        case .failed: return "xmark.shield.fill"
        }
    }

    private var sleepPreventionColor: Color {
        switch sleepManager.health {
        case .inactive: return .secondary
        case .active: return .green
        case .degraded: return .orange
        case .failed: return .red
        }
    }
}
