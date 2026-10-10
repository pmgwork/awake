//
//  ModeSelectorView.swift
//  Awake
//

import SwiftUI

struct ModeSelectorView: View {
    @ObservedObject var coordinator: AwakeCoordinator
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Keep Awake Mode"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(modeOrder) { mode in
                    Button {
                        coordinator.selectMode(mode)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: settings.selectedMode == mode
                                  ? "largecircle.fill.circle"
                                  : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(settings.selectedMode == mode ? Color.orange : Color.secondary)
                            Text(mode.displayName)
                                .foregroundStyle(.primary)
                            if mode == .timer, settings.selectedMode == .timer,
                               coordinator.isActive, let end = coordinator.timerEndDate {
                                Spacer(minLength: 8)
                                Text(timerInterval: Date()...max(end, Date()), countsDown: true)
                                    .font(.system(size: 10))
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(settings.selectedMode == mode ? .isSelected : [])

                    if mode == .timer, settings.selectedMode == .timer {
                        timerPresetsGrid
                            .padding(.leading, 22)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private let modeOrder: [KeepAwakeModeType] = [
        .whileAgentRunning,
        .timer,
        .whileDownloading,
        .indefinitely
    ]

    private var timerPresetsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TimerPreset.standardPresets) { preset in
                        Button(action: {
                            coordinator.setTimerDuration(preset.duration)
                        }) {
                            Text(L10n.string(preset.title))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(settings.selectedTimerDuration == preset.duration ? .orange : nil)
                    }
                }
            }
        }
    }
}
