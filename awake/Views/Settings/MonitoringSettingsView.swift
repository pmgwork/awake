//
//  MonitoringSettingsView.swift
//  Awake
//

import SwiftUI
import AppKit

/// What the "While Agent Is Running", "While Downloading" and "While
/// Rendering" conditions watch.
struct MonitoringSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var integrationManager: HookIntegrationManager

    @ObservedObject private var afterEffects = AfterEffectsRenderIntegration.shared
    @State private var pendingAEAction = false

    @State private var pendingAction: PendingAction?
    @State private var blenderStatus = BlenderRenderIntegration.Status.unlinked
    @State private var pendingBlenderAction: BlenderAction?
    @State private var blenderError: String?
    @State private var showBlenderRestart = false

    private enum BlenderAction { case install, reinstall, uninstall }

    var body: some View {
        Form {
            Section {
                // Saved lists keep their old order, so sort by provider.
                ForEach(settings.monitoredAgents
                    .filter { $0.isPreset && $0.provider != nil }
                    .sorted { $0.provider!.sortIndex < $1.provider!.sortIndex }) { agent in
                    providerRow(agent)
                }
            } header: {
                Text(L10n.string("Agents"))
            } footer: {
                if let error = integrationManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Section {
                ForEach(RenderApp.allCases) { app in
                    renderAppRow(app)
                }
            } header: {
                Text(L10n.string("Rendering"))
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
                Text(L10n.string("Downloads"))
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
        .confirmationDialog(L10n.format("Link %@?", "Adobe After Effects"), isPresented: $pendingAEAction,
                            titleVisibility: .visible) {
            Button(L10n.string("Link")) {
                afterEffects.link()
                settings.enabledRenderApps.insert(.afterEffects)
            }
            Button(L10n.string("Cancel"), role: .cancel) { }
        } message: {
            Text(L10n.string("Awake connects to Adobe After Effects through macOS Automation. Allow Automation access and enable Allow Scripts to Write Files and Access Network in Adobe After Effects. Your project is not saved or changed."))
        }
        .onAppear { refreshIntegrationStatuses() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshIntegrationStatuses()
        }
        .confirmationDialog(
            pendingBlenderAction == .uninstall ? L10n.format("Unlink %@?", "Blender") : L10n.format("Link %@?", "Blender"),
            isPresented: Binding(
                get: { pendingBlenderAction != nil },
                set: { if !$0 { pendingBlenderAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingBlenderAction {
                Button(action == .uninstall ? L10n.string("Remove Awake Integration") : L10n.string("Update Configuration"),
                       role: action == .uninstall ? .destructive : nil) {
                    performBlenderAction(action)
                    pendingBlenderAction = nil
                }
                Button(L10n.string("Cancel"), role: .cancel) { pendingBlenderAction = nil }
            }
        } message: {
            Text(L10n.string(pendingBlenderAction == .uninstall
                ? "Awake removes only its Blender startup scripts. Restart Blender to finish unlinking."
                : "Awake adds a startup script to each existing Blender version. Restart Blender after linking."))
        }
        .alert(L10n.string("Blender Integration"), isPresented: Binding(
            get: { blenderError != nil || showBlenderRestart },
            set: { if !$0 { blenderError = nil; showBlenderRestart = false } }
        )) {
            Button(L10n.string("OK")) { blenderError = nil; showBlenderRestart = false }
        } message: {
            Text(blenderError ?? L10n.string("Restart Blender to apply the integration change."))
        }
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

    /// A status line appears only when something needs
    /// attention. Turning on an unlinked agent links it after confirmation.
    private func providerRow(_ agent: MonitoredAgent) -> some View {
        let provider = agent.provider!
        let status = integrationManager.status(for: provider)
        let toolInstalled = integrationManager.isToolInstalled(provider)
        let canMonitor = toolInstalled && (status == .linked || status == .unverified)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .fontWeight(.medium)
                if let note = providerNote(status: status, installed: toolInstalled) {
                    Text(note.text)
                        .font(.callout)
                        .foregroundStyle(note.color)
                }
            }

            Spacer()

            integrationMenu(for: provider, status: status)
                .disabled(!toolInstalled)

            Toggle(L10n.format("Monitor %@", provider.displayName), isOn: Binding(
                get: { canMonitor && agent.isEnabled },
                set: { enabled in
                    if canMonitor {
                        if enabled != agent.isEnabled { settings.toggleAgent(id: agent.id) }
                    } else if enabled && toolInstalled {
                        // Linking (or repairing) turns monitoring on when it succeeds.
                        pendingAction = PendingAction(provider: provider, kind: .install)
                    }
                }
            ))
            .labelsHidden()
            .disabled(!toolInstalled)
        }
    }

    private func providerNote(status: HookIntegrationStatus,
                              installed: Bool) -> (text: String, color: Color)? {
        guard installed else { return (L10n.string("CLI not installed"), .secondary) }
        if status == .needsRepair { return (status.label, .orange) }
        return nil
    }

    private func integrationMenu(for provider: AgentProvider, status: HookIntegrationStatus) -> some View {
        actionsMenu {
            if status == .unlinked || status == .needsRepair {
                Button(status == .needsRepair ? L10n.string("Repair") : L10n.string("Link")) {
                    pendingAction = PendingAction(provider: provider, kind: .install)
                }
            } else {
                Button(L10n.string("Test")) { integrationManager.test(provider) }
                Button(L10n.string("Reinstall")) {
                    pendingAction = PendingAction(provider: provider, kind: .install)
                }
                Divider()
                Button(L10n.string("Unlink"), role: .destructive) {
                    pendingAction = PendingAction(provider: provider, kind: .uninstall)
                }
            }
        }
    }

    private func renderAppRow(_ app: RenderApp) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .fontWeight(.medium)
                if app == .afterEffects, let error = afterEffects.lastError {
                    Text(error).font(.callout).foregroundStyle(.orange)
                } else if app == .afterEffects && !afterEffects.isLinked {
                    Text(L10n.string("Link to monitor the render queue."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if app == .blender && blenderStatus == .needsRepair {
                    Text(L10n.string("Needs repair"))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if app == .blender {
                blenderIntegrationMenu
            } else if app == .afterEffects {
                actionsMenu {
                    if afterEffects.isLinked {
                        Button(L10n.string("Reconnect")) {
                            afterEffects.setEnabled(false)
                            afterEffects.setEnabled(RenderMonitor.shared.enabledApps.contains(.afterEffects)
                                && settings.renderCoolingEnabled)
                        }
                        Divider()
                        Button(L10n.string("Unlink"), role: .destructive) { afterEffects.unlink() }
                    } else {
                        Button(L10n.string("Link")) { pendingAEAction = true }
                    }
                }
            }

            Toggle(L10n.format("Monitor %@", app.displayName), isOn: Binding(
                get: { settings.enabledRenderApps.contains(app) && (app != .blender || blenderStatus == .linked) },
                set: { enabled in
                    if app == .afterEffects && enabled && !afterEffects.isLinked {
                        pendingAEAction = true
                    } else if app == .blender && enabled && blenderStatus != .linked {
                        pendingBlenderAction = .install
                    } else if enabled { settings.enabledRenderApps.insert(app) }
                    else { settings.enabledRenderApps.remove(app) }
                }
            ))
            .labelsHidden()
        }
    }

    private var blenderIntegrationMenu: some View {
        actionsMenu {
            Button(blenderStatus == .unlinked ? L10n.string("Link") : L10n.string("Reinstall")) {
                pendingBlenderAction = blenderStatus == .unlinked ? .install : .reinstall
            }
            if blenderStatus != .unlinked {
                Divider()
                Button(L10n.string("Unlink"), role: .destructive) {
                    pendingBlenderAction = .uninstall
                }
            }
        }
    }

    private func actionsMenu<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Label(L10n.string("Actions"), systemImage: "ellipsis.circle")
        }
        .labelStyle(.iconOnly)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.string("Actions"))
    }

    private func refreshIntegrationStatuses() {
        integrationManager.refreshStatuses()
        blenderStatus = BlenderRenderIntegration.status()
    }

    private func performBlenderAction(_ action: BlenderAction) {
        do {
            if action != .uninstall {
                try BlenderRenderIntegration.install()
                if action == .install { settings.enabledRenderApps.insert(.blender) }
            } else {
                try BlenderRenderIntegration.uninstall()
                settings.enabledRenderApps.remove(.blender)
            }
            showBlenderRestart = true
        } catch {
            blenderError = error.localizedDescription
        }
        blenderStatus = BlenderRenderIntegration.status()
        RenderMonitor.shared.updateEnabledApps(settings.enabledRenderApps)
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
