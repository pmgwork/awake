//
//  ModeSelectorView.swift
//  Awake
//

import SwiftUI

struct ModeSelectorView: View {
    @ObservedObject var coordinator: AwakeCoordinator
    @ObservedObject var settings: SettingsStore
    @State private var showingCustomDurationPicker: Bool = false
    @State private var customMinutes: Int = 45

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keep Awake Mode")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                // While Agent is Running
                modeButton(
                    type: .whileAgentRunning,
                    title: "While Agent is Running"
                )

                // Indefinitely
                modeButton(
                    type: .indefinitely,
                    title: "Indefinitely"
                )

                // For Duration (Timer)
                modeButton(
                    type: .timer,
                    title: "For Duration"
                )

                if settings.selectedMode == .timer {
                    timerPresetsGrid
                        .padding(.leading, 22)
                        .padding(.top, 2)
                    if coordinator.isActive, let endTime = coordinator.formattedTimerEndTime {
                        Text(L10n.format("Ends at %@", endTime))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.leading, 22)
                    }
                }
            }
        }
    }

    private func modeButton(type: KeepAwakeModeType, title: LocalizedStringKey) -> some View {
        Button(action: {
            coordinator.selectMode(type)
        }) {
            HStack(spacing: 8) {
                Image(systemName: settings.selectedMode == type ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(settings.selectedMode == type ? .accentColor : .secondary)
                    .font(.system(size: 13))

                Text(title)
                    .font(.system(size: 13, weight: settings.selectedMode == type ? .medium : .regular))
                    .foregroundColor(.primary)

                Spacer()

            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timerPresetsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TimerPreset.standardPresets) { preset in
                        Button(action: {
                            coordinator.setTimerDuration(preset.duration)
                        }) {
                            Text(preset.title)
                                .font(.system(size: 10, weight: settings.selectedTimerDuration == preset.duration ? .bold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(settings.selectedTimerDuration == preset.duration ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                .foregroundColor(settings.selectedTimerDuration == preset.duration ? .accentColor : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
