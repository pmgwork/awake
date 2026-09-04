//
//  RunningAgentsView.swift
//  Awake
//

import SwiftUI

struct RunningAgentsView: View {
    @ObservedObject var eventMonitor: AgentEventMonitor
    @ObservedObject var integrationManager: HookIntegrationManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Monitored Agents")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if eventMonitor.hasActiveSession {
                    Text(L10n.format("%d running", eventMonitor.activeSessionCount))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            }

            let enabledAgents = settings.monitoredAgents.filter { $0.isEnabled && $0.provider != nil }
            if enabledAgents.isEmpty {
                Text("No agents enabled. Configure in Settings.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 4) {
                    ForEach(enabledAgents) { agent in
                        let provider = agent.provider!
                        let sessionCount = eventMonitor.activeSessionCountByProvider[provider, default: 0]
                        let isRunning = sessionCount > 0
                        let integrationStatus = integrationManager.status(for: provider)
                        HStack {
                            Circle()
                                .fill(isRunning ? Color.green : integrationStatus == .linked ? Color.gray.opacity(0.5) : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(agent.name)
                                .font(.system(size: 12, weight: isRunning ? .medium : .regular))
                                .foregroundColor(isRunning ? .primary : .secondary)
                            Spacer()
                            if isRunning {
                                Text(sessionCount == 1 ? "Running" : "\(sessionCount) sessions")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.green)
                            } else if integrationStatus != .linked {
                                Text(integrationStatus.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
    }
}
