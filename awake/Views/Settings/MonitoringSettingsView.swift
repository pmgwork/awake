//
//  MonitoringSettingsView.swift
//  Awake
//

import SwiftUI
import AppKit

/// What the "While Agent Is Running" and "While Downloading" modes watch.
struct MonitoringSettingsView: View {
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
                Text(L10n.string("Agents"))
            } footer: {
                HStack {
                    Button {
                        eventMonitor.reloadNow()
                        integrationManager.refreshStatuses()
                    } label: {
                        Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.link)

                    Spacer(minLength: 12)

                    if let error = integrationManager.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section {
                LabeledContent {
                    HStack {
                        Text(settings.downloadFolderPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(L10n.string("Choose…")) {
                            chooseDownloadFolder()
                        }
                    }
                } label: {
                    Text(L10n.string("Monitored Folder"))
                }
            } header: {
                Text(L10n.string("Download Monitoring"))
            } footer: {
                Text(L10n.string("Awake looks for the temporary files that browsers create for unfinished downloads."))
            }

            let customAgents = settings.monitoredAgents.filter { !$0.isPreset }
            if !customAgents.isEmpty {
                Section {
                    ForEach(customAgents) { agent in
                        LabeledContent {
                            Button(L10n.string("Delete"), role: .destructive) {
                                settings.deleteAgent(id: agent.id)
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(agent.name)
                                Text(L10n.string("Custom agents need hook integration, so they aren't supported in this version."))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(L10n.string("Saved Custom Agents"))
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
                  : L10n.string("Link this agent to monitor it."))

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

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose Download Folder")
        panel.prompt = L10n.string("Choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.downloadFolderPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadFolderPath = url.path
        }
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
                    "Awake backs up your configuration and changes only its own %@ entry.",
                    provider.integrationKind
                )
                : L10n.string("Only the settings and files that Awake added are removed.")
        }
    }
}
