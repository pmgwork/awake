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
            HStack {
                Text(L10n.string("Cooling Mode"))
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                Spacer()
                if settings.coolingMode == .timed, settings.coolingArmed,
                   let end = coordinator.forcedCoolingEndDate {
                    Text(timerInterval: Date()...max(end, Date()), countsDown: true)
                        .font(.system(size: 10))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                automaticCondition("While Keep Awake Is On", enabled: settings.automaticCoolingEnabled,
                                   active: coordinator.isAutomaticCoolingActive,
                                   setEnabled: coordinator.setAutomaticCoolingEnabled)
                automaticCondition("While Rendering", enabled: settings.renderCoolingEnabled,
                                   active: coordinator.isRenderCoolingActive,
                                   help: "Cools during rendering or sustained Media Encoder load.",
                                   setEnabled: coordinator.setRenderCoolingEnabled)
            }

            durationPresets
                .padding(.top, 4)
        }
    }

    private func automaticCondition(_ title: String, enabled: Bool, active: Bool,
                                    help: String? = nil,
                                    setEnabled: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 7) {
            Text(L10n.string(title))
                .foregroundStyle(.primary)
            if active {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            Toggle(L10n.string(title), isOn: Binding(get: { enabled }, set: setEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.blue)
                .fixedSize()
                .disabled(coordinator.isCoolingBlockedByLowBattery)
        }
        .frame(minHeight: 20)
        .help(help.map { L10n.string($0) } ?? "")
    }

    private var durationPresets: some View {
        HStack(spacing: 4) {
            Button {
                coordinator.selectCoolingMode(.forced)
            } label: {
                presetLabel("∞", selected: settings.coolingMode == .forced, infinity: true)
            }
            .help(L10n.string("Indefinitely"))
            .accessibilityLabel(L10n.string("Indefinitely"))
            .accessibilityAddTraits(settings.coolingMode == .forced ? .isSelected : [])

            ForEach(SettingsStore.forcedCoolingDurations, id: \.self) { duration in
                let selected = settings.coolingMode == .timed && settings.forcedCoolingDuration == duration
                Button {
                    coordinator.selectCoolingMode(.timed)
                    coordinator.setCoolingDuration(duration)
                } label: {
                    presetLabel(L10n.string("\(Int(duration / 60))m"), selected: selected)
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
            .foregroundStyle(selected ? Color.blue : Color.primary)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.blue.opacity(0.12) : Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 5))
    }
}
