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
            HStack {
                Text(L10n.string("Keep Awake Mode"))
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                Spacer()
                if coordinator.isManualKeepAwakeActive, let end = coordinator.timerEndDate {
                    Text(timerInterval: Date()...max(end, Date()), countsDown: true)
                        .font(.system(size: 10))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                automaticCondition("While Agent Is Running", enabled: settings.agentMonitoringEnabled,
                                   active: coordinator.isAgentKeepAwakeActive,
                                   countdownEnd: coordinator.agentCompletionGraceEndDate,
                                   setEnabled: coordinator.setAgentMonitoringEnabled)
                automaticCondition("While Downloading", enabled: settings.downloadMonitoringEnabled,
                                   active: coordinator.isDownloadKeepAwakeActive,
                                   setEnabled: coordinator.setDownloadMonitoringEnabled)

                timerPresetsRow
                    .padding(.top, 4)
            }
        }
    }

    private func automaticCondition(_ title: String, enabled: Bool, active: Bool,
                                    countdownEnd: Date? = nil,
                                    setEnabled: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 7) {
            Text(L10n.string(title))
                .foregroundStyle(.primary)
            if active {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            if enabled, let end = countdownEnd, end > Date() {
                Text(timerInterval: Date()...end, countsDown: true)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
                    .help(L10n.string("Keeping Awake After Completion"))
                    .accessibilityLabel(L10n.string("Keeping Awake After Completion"))
            }
            Toggle(L10n.string(title), isOn: Binding(get: { enabled }, set: setEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.orange)
                .fixedSize()
                .accessibilityValue(L10n.string(enabled ? (active ? "Keeping Awake" : "Waiting for Activity") : "Off"))
        }
        .frame(minHeight: 20)
        .help(L10n.string(enabled ? (active ? "Keeping Awake" : "Waiting for Activity") : "Off"))
    }

    private var timerPresetsRow: some View {
        HStack(spacing: 4) {
            Button {
                coordinator.selectMode(.indefinitely)
            } label: {
                presetLabel("∞", selected: settings.selectedMode == .indefinitely, infinity: true)
            }
            .help(L10n.string("Indefinitely"))
            .accessibilityLabel(L10n.string("Indefinitely"))
            .accessibilityAddTraits(settings.selectedMode == .indefinitely ? .isSelected : [])

            ForEach(TimerPreset.standardPresets) { preset in
                let selected = settings.selectedMode == .timer && settings.selectedTimerDuration == preset.duration
                Button {
                    coordinator.selectMode(.timer)
                    coordinator.setTimerDuration(preset.duration)
                } label: {
                    presetLabel(L10n.string(preset.title), selected: selected)
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .buttonStyle(.plain)
    }

    private func presetLabel(_ title: String, selected: Bool, infinity: Bool = false) -> some View {
        Text(title)
            .font(.system(size: infinity ? 16 : 11, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .foregroundStyle(selected ? Color.orange : Color.primary)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.orange.opacity(0.12) : Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 5))
    }
}
