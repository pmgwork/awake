import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var eventMonitor: AgentEventMonitor
    @ObservedObject var integrationManager: HookIntegrationManager
    var onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var pendingProvider: AgentProvider?

    private enum Step: Int, CaseIterable {
        case welcome
        case preferences
        case agents
        case completion

        var title: String {
            switch self {
            case .welcome: return "Welcome to Awake"
            case .preferences: return "General Preferences"
            case .agents: return "AI Agent Hook Integrations"
            case .completion: return "You're Ready"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            contentArea

            Divider()

            HStack {
                Button(L10n.string("Back")) {
                    moveBackward()
                }
                .disabled(step == .welcome)

                Text(L10n.format("Step %d of %d", step.rawValue + 1, Step.allCases.count))
                    .foregroundStyle(.secondary)

                Spacer()

                if step != .completion {
                    Button(L10n.string("Set Up Later")) {
                        finish()
                    }
                }

                Button(L10n.string(step == .completion ? "Done" : "Continue")) {
                    if step == .completion {
                        finish()
                    } else {
                        moveForward()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 500)
        .onAppear {
            refreshStatus()
        }
        .confirmationDialog(
            L10n.string("Hook Integration"),
            isPresented: Binding(
                get: { pendingProvider != nil },
                set: { if !$0 { pendingProvider = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let provider = pendingProvider {
                Button(L10n.string("Update Configuration")) {
                    integrationManager.install(provider)
                    pendingProvider = nil
                }
            }
            Button(L10n.string("Cancel"), role: .cancel) {
                pendingProvider = nil
            }
        } message: {
            if let provider = pendingProvider {
                Text(L10n.format(
                    "Awake will back up and update only its own %@ entry in your user configuration.",
                    provider.integrationKind
                ))
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if step == .welcome {
            welcomePage
        } else if step == .completion {
            completionPage
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.string(step.title))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                Form {
                    pageContent
                }
                .formStyle(.grouped)
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch step {
        case .welcome:
            welcomePage
        case .preferences:
            preferencesPage
        case .agents:
            agentsPage
        case .completion:
            completionPage
        }
    }

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    Text(L10n.string("Welcome to Awake"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)

                    Text(L10n.string("Awake keeps your Mac awake while AI coding agents run, even with the lid closed. This short setup covers the essentials."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 20) {
                    welcomeFeature(
                        symbol: "cpu",
                        title: "While Agent is Running",
                        description: "Awake follows activity from your linked agents."
                    )
                    welcomeFeature(
                        symbol: "timer",
                        title: "For Duration",
                        description: "Keep working for a set time, then return to normal sleep."
                    )
                    welcomeFeature(
                        symbol: "infinity",
                        title: "Indefinitely",
                        description: "Stay awake until you choose to stop."
                    )
                }
                .frame(maxWidth: 440, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
        }
    }

    private func welcomeFeature(symbol: String, title: String, description: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(title))
                    .fontWeight(.semibold)
                Text(L10n.string(description))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
        }
    }

    private var preferencesPage: some View {
        Group {
            Section(L10n.string("General")) {
                Toggle(L10n.string("Enable Notifications"), isOn: $settings.notificationsEnabled)
                if notificationManager.authorizationStatus == .denied {
                    Label(
                        L10n.string("Notifications are disabled in System Settings."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
                Toggle(L10n.string("Launch Awake at Login"), isOn: $settings.launchAtLogin)
            }

            Section(L10n.string("Display During Sessions")) {
                Toggle(L10n.string("Prevent Display Sleep"), isOn: $settings.preventDisplaySleep)
                Toggle(
                    L10n.string("Prevent Screen Saver & Automatic Lock"),
                    isOn: $settings.preventScreenSaver
                )
                Text(L10n.string("These preferences apply only while Awake is actively preventing system sleep."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var agentsPage: some View {
        Group {
            Text(L10n.string("Awake reacts only to lifecycle events from linked agents. A running CLI process alone is never treated as active."))
                .foregroundStyle(.secondary)

            Section(L10n.string("Supported Providers")) {
                ForEach(AgentProvider.allCases) { provider in
                    providerRow(provider)
                }
            }

            if let error = integrationManager.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private var completionPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(L10n.string("You're Ready"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.string("Left-click the menu-bar cup for status, right-click to toggle Awake. You can revisit settings anytime from Settings...."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func providerRow(_ provider: AgentProvider) -> some View {
        let agent = settings.monitoredAgents.first { $0.provider == provider }
        let status = integrationManager.status(for: provider)
        let isInstalled = integrationManager.isToolInstalled(provider)
        let canMonitor = isInstalled && (status == .linked || status == .unverified)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                Text(isInstalled ? status.label : L10n.string("CLI not installed"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(
                L10n.format("Monitor %@", provider.displayName),
                isOn: Binding(
                    get: { canMonitor && (agent?.isEnabled ?? false) },
                    set: { enabled in
                        if let agent, canMonitor, enabled != agent.isEnabled {
                            settings.toggleAgent(id: agent.id)
                        }
                    }
                )
            )
            .labelsHidden()
            .disabled(!canMonitor)

            switch status {
            case .unlinked, .needsRepair:
                Button(status == .needsRepair ? L10n.string("Repair") : L10n.string("Link")) {
                    pendingProvider = provider
                }
                .disabled(!isInstalled)
                .frame(minWidth: 64)
            case .unverified, .linked:
                Button(L10n.string("Test")) {
                    integrationManager.test(provider)
                }
                .frame(minWidth: 64)
            }
        }
    }

    private func moveForward() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
        if next == .agents { integrationManager.refreshStatuses() }
    }

    private func moveBackward() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func refreshStatus() {
        notificationManager.refreshAuthorizationStatus()
        integrationManager.refreshStatuses()
    }

    private func finish() {
        settings.completeOnboarding()
        onFinished()
    }
}
