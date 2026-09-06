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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("AI Agent Hook Integrations"))
                    .font(.headline)
                Text(L10n.string("Awake reacts only to lifecycle events from linked agents. A running CLI process alone is never treated as active."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            List {
                Section(header: Text(L10n.string("Supported Providers"))) {
                    ForEach(settings.monitoredAgents.filter { $0.isPreset && $0.provider != nil }) { agent in
                        providerRow(agent)
                    }
                }

                let customAgents = settings.monitoredAgents.filter { !$0.isPreset }
                if !customAgents.isEmpty {
                    Section(header: Text(L10n.string("Saved Custom Agents"))) {
                        ForEach(customAgents) { agent in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name).font(.system(size: 13, weight: .medium))
                                    Text(L10n.string("Hook integration is required; custom agents are not available in this release."))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    settings.deleteAgent(id: agent.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(height: 285)

            HStack {
                Button(L10n.string("Reset Provider Selection")) { settings.resetToDefaults() }
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    eventMonitor.reloadNow()
                    integrationManager.refreshStatuses()
                } label: {
                    Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                }
            }

            if let error = integrationManager.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.string("Hook Event Status"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(L10n.format("%d active sessions", eventMonitor.activeSessionCount))
                        .font(.caption)
                        .foregroundColor(eventMonitor.hasActiveSession ? .green : .secondary)
                }
                ForEach(AgentProvider.allCases) { provider in
                    HStack {
                        Circle()
                            .fill(eventMonitor.activeSessionCountByProvider[provider, default: 0] > 0 ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(provider.displayName).font(.caption.weight(.medium))
                        Spacer()
                        if let date = eventMonitor.lastEventAtByProvider[provider] {
                            Text(L10n.format(
                                "Last event %@",
                                date.formatted(.relative(presentation: .named))
                            ))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text(L10n.string("No events received"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
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
        let activeCount = eventMonitor.activeSessionCountByProvider[provider, default: 0]
        return HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { agent.isEnabled },
                set: { _ in settings.toggleAgent(id: agent.id) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(provider.integrationKind) · \(status.label)")
                        .font(.system(size: 10))
                        .foregroundColor(status == .linked ? .secondary : .orange)
                }
            }
            .toggleStyle(.checkbox)

            Spacer()

            if activeCount > 0 {
                Text(L10n.format("%d active", activeCount))
                    .font(.caption2.bold())
                    .foregroundColor(.green)
            }

            if status == .unlinked || status == .needsRepair {
                Button(status == .needsRepair ? L10n.string("Repair") : L10n.string("Link")) {
                    pendingAction = PendingAction(provider: provider, kind: .install)
                }
            } else {
                HStack(spacing: 6) {
                    Button(L10n.string("Test")) { integrationManager.test(provider) }
                    Menu {
                        Button(L10n.string("Reinstall")) { pendingAction = PendingAction(provider: provider, kind: .install) }
                        Button(L10n.string("Unlink"), role: .destructive) { pendingAction = PendingAction(provider: provider, kind: .uninstall) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.vertical, 3)
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
