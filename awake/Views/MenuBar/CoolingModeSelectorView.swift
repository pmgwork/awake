//
//  CoolingModeSelectorView.swift
//  Awake
//

import SwiftUI

struct CoolingModeSelectorView: View {
    @ObservedObject var coordinator: AwakeCoordinator
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Cooling Mode"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(CoolingMode.allCases) { mode in
                    Button {
                        coordinator.selectCoolingMode(mode)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: settings.coolingMode == mode
                                  ? "largecircle.fill.circle"
                                  : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(settings.coolingMode == mode ? Color.blue : Color.secondary)
                            Text(mode.displayName)
                                .foregroundStyle(.primary)
                            if mode == .timed, settings.coolingMode == .timed,
                               settings.coolingArmed, let end = coordinator.forcedCoolingEndDate {
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
                    .accessibilityAddTraits(settings.coolingMode == mode ? .isSelected : [])

                    if mode == .timed, settings.coolingMode == .timed {
                        durationPresets
                            .padding(.leading, 22)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var durationPresets: some View {
        HStack(spacing: 6) {
            ForEach(SettingsStore.forcedCoolingDurations, id: \.self) { duration in
                Button {
                    coordinator.setCoolingDuration(duration)
                } label: {
                    Text(L10n.string("\(Int(duration / 60))m"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(settings.forcedCoolingDuration == duration ? .blue : nil)
            }
        }
    }
}
