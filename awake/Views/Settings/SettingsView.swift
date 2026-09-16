//
//  SettingsView.swift
//  Awake
//

import SwiftUI
import Combine

/// The panes shown in the settings window's compact tab bar.
public enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case agents
    case cooling

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return L10n.string("General")
        case .agents: return L10n.string("Agents")
        case .cooling: return L10n.string("Cooling")
        }
    }

    public var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .agents: return "cpu"
        case .cooling: return "wind"
        }
    }

}

/// Observable selection shared between the tab bar and its content.
@MainActor
public final class SettingsTabSelection: ObservableObject {
    @Published public var tab: SettingsTab = .general

    public init() {}
}

struct SettingsView: View {
    @ObservedObject var coordinator: AwakeCoordinator
    @ObservedObject var selection: SettingsTabSelection

    var body: some View {
        VStack(spacing: 0) {
            settingsTabBar
            Divider()

            Group {
                switch selection.tab {
                case .general:
                    GeneralSettingsView(
                        settings: coordinator.settings,
                        notificationManager: NotificationManager.shared,
                        screenBehaviorManager: coordinator.screenBehaviorManager,
                        updater: AppUpdater.shared,
                        shortcutManager: coordinator.shortcutManager
                    )
                case .agents:
                    AgentSettingsView(
                        settings: coordinator.settings,
                        eventMonitor: coordinator.eventMonitor,
                        integrationManager: coordinator.hookIntegrationManager
                    )
                case .cooling:
                    CoolingSettingsView(
                        settings: coordinator.settings,
                        fanController: coordinator.fanController,
                        thermalMonitor: coordinator.thermalMonitor
                    )
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 600)
    }

    private var settingsTabBar: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection.tab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: .regular))
                            .frame(height: 21)

                        Text(tab.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection.tab == tab ? .primary : .secondary)
                    .frame(width: 72, height: 50)
                    .background {
                        if selection.tab == tab {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.1))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.tab == tab ? .isSelected : [])
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
