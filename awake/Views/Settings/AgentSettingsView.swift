//
//  AgentSettingsView.swift
//  Awake
//

import SwiftUI

struct AgentSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var eventMonitor: AgentEventMonitor
    @ObservedObject var integrationManager: HookIntegrationManager

    @State private var pendingAction: PendingAction?

    var body: some View {
        Form {
            Section {
                ForEach(settings.monitoredAgents.filter { $0.isPreset && $0.provider != nil }) { agent in
                    providerRow(agent)
                }
            } header: {
                Text(L10n.string("Supported Providers"))
            } footer: {
                Text(L10n.string("Awake reacts only to lifecycle events from linked agents. A running CLI process alone is never treated as active."))
            }

            let customAgents = settings.monitoredAgents.filter { !$0.isPreset }
            if !customAgents.isEmpty {
                Section(L10n.string("Saved Custom Agents")) {
                    ForEach(customAgents) { agent in
                        LabeledContent {
                            Button(L10n.string("Delete"), role: .destructive) {
                                settings.deleteAgent(id: agent.id)
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(agent.name)
                                Text(L10n.string("Hook integration is required; custom agents are not available in this release."))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                if eventMonitor.hasActiveSession {
                    ForEach(activeProviders) { provider in
                        LabeledContent {
                            Text(L10n.format(
                                "%d active",
                                eventMonitor.activeSessionCountByProvider[provider, default: 0]
                            ))
                            .foregroundStyle(.green)
                        } label: {
                            Label(provider.displayName, systemImage: "bolt.fill")
                        }
                    }
                } else {
                    Text(L10n.string("No active agent sessions."))
                        .foregroundStyle(.secondary)
                }

                Button {
                    eventMonitor.reloadNow()
                    integrationManager.refreshStatuses()
                } label: {
                    Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                }
            } header: {
                Text(L10n.string("Current Activity"))
            } footer: {
                if let latestEventDate {
                    Text(L10n.format("Last event %@", latestEventDate.formatted(.relative(presentation: .named))))
                }
            }

            if let error = integrationManager.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(integrationManager.isWorking)
        .confirmationDialog(
            pendingAction?.title ?? L10n.string("Hook Integration"),
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingAction {
                Button(action.buttonTitle, role: action.kind == .uninstall ? .destructive : nil) {
                    if action.kind == .uninstall {
                        integrationManager.uninstall(action.provider)
                    } else {
                        integrationManager.install(action.provider)
                    }
                    pendingAction = nil
                }
                Button(L10n.string("Cancel"), role: .cancel) { pendingAction = nil }
            }
        } message: {
            Text(pendingAction?.message ?? "")
        }
    }

    private func providerRow(_ agent: MonitoredAgent) -> some View {
        let provider = agent.provider!
        let status = integrationManager.status(for: provider)
        let toolInstalled = integrationManager.isToolInstalled(provider)
        let activeCount = eventMonitor.activeSessionCountByProvider[provider, default: 0]
        let canMonitor = toolInstalled && (status == .linked || status == .unverified)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .fontWeight(.medium)
                Text(providerStatusText(provider, status: status, installed: toolInstalled, activeCount: activeCount))
                    .font(.callout)
                    .foregroundStyle(activeCount > 0 ? .green : .secondary)
            }

            Spacer()

            Toggle(L10n.format("Monitor %@", provider.displayName), isOn: Binding(
                get: { canMonitor && agent.isEnabled },
                set: { enabled in
                    guard canMonitor, enabled != agent.isEnabled else { return }
                    settings.toggleAgent(id: agent.id)
                }
            ))
            .labelsHidden()
            .disabled(!canMonitor)
            .help(canMonitor
                  ? L10n.format("Monitor %@", provider.displayName)
                  : L10n.string("Link this provider before enabling monitoring."))

            Menu {
                if status == .unlinked || status == .needsRepair {
                    Button(status == .needsRepair ? L10n.string("Repair") : L10n.string("Link")) {
                        pendingAction = PendingAction(provider: provider, kind: .install)
                    }
                } else {
                    Button(L10n.string("Test")) { integrationManager.test(provider) }
                    Divider()
                    Button(L10n.string("Reinstall")) {
                        pendingAction = PendingAction(provider: provider, kind: .install)
                    }
                    Button(L10n.string("Unlink"), role: .destructive) {
                        pendingAction = PendingAction(provider: provider, kind: .uninstall)
                    }
                }
            } label: {
                Label(L10n.string("Actions"), systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!toolInstalled)
            .help(toolInstalled ? L10n.string("Actions") : L10n.string("CLI not installed"))
        }
    }

    private var activeProviders: [AgentProvider] {
        AgentProvider.allCases.filter {
            eventMonitor.activeSessionCountByProvider[$0, default: 0] > 0
        }
    }

    private var latestEventDate: Date? {
        eventMonitor.lastEventAtByProvider.values.max()
    }

    private func providerStatusText(
        _ provider: AgentProvider,
        status: HookIntegrationStatus,
        installed: Bool,
        activeCount: Int
    ) -> String {
        guard installed else { return L10n.string("CLI not installed") }
        let integration = "\(provider.integrationKind) · \(status.label)"
        guard activeCount > 0 else { return integration }
        return "\(L10n.format("%d active", activeCount)) · \(integration)"
    }

    private struct PendingAction: Identifiable {
        enum Kind { case install, uninstall }
        let provider: AgentProvider
        let kind: Kind
        var id: String { "\(provider.rawValue)-\(kind)" }
        var title: String {
            kind == .install
                ? L10n.format("Link %@?", provider.displayName)
                : L10n.format("Unlink %@?", provider.displayName)
        }
        var buttonTitle: String {
            kind == .install
                ? L10n.string("Update Configuration")
                : L10n.string("Remove Awake Integration")
        }
        var message: String {
            kind == .install
                ? L10n.format(
                    "Awake will back up and update only its own %@ entry in your user configuration.",
                    provider.integrationKind
                )
                : L10n.string("Only the configuration and files owned by Awake will be removed.")
        }
    }
}
