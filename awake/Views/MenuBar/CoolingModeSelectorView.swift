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

            HStack(spacing: 7) {
                Text(L10n.string("While Keep Awake Is On"))
                    .foregroundStyle(.primary)
                if coordinator.isAutomaticCoolingActive {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                Toggle(L10n.string("While Keep Awake Is On"), isOn: Binding(
                    get: { settings.automaticCoolingEnabled },
                    set: { coordinator.setAutomaticCoolingEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.blue)
                .fixedSize()
                .disabled(coordinator.isCoolingBlockedByLowBattery)
            }
            .frame(minHeight: 20)

            durationPresets
                .padding(.top, 4)
        }
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
