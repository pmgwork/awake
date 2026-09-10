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
            Text(L10n.string("Keep Awake Mode"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: Binding(
                    get: { settings.selectedMode },
                    set: { coordinator.selectMode($0) }
                )) {
                    Text(L10n.string("While Agent is Running")).tag(KeepAwakeModeType.whileAgentRunning)
                    Text(L10n.string("Indefinitely")).tag(KeepAwakeModeType.indefinitely)
                    Text(L10n.string("For Duration")).tag(KeepAwakeModeType.timer)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

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

    private var timerPresetsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TimerPreset.standardPresets) { preset in
                        Button(action: {
                            coordinator.setTimerDuration(preset.duration)
                        }) {
                            Text(preset.title)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(settings.selectedTimerDuration == preset.duration ? .accentColor : nil)
                    }
                }
            }
        }
    }
}
