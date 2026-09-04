//
//  RunningAgentsView.swift
//  Awake
//

import SwiftUI

struct RunningAgentsView: View {
    @ObservedObject var processMonitor: ProcessMonitor
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Monitored Agents")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if processMonitor.hasRunningAgent {
                    Text(L10n.format("%d running", processMonitor.runningAgentCount))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            }

            let enabledAgents = settings.monitoredAgents.filter { $0.isEnabled }
            if enabledAgents.isEmpty {
                Text("No agents enabled. Configure in Settings.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 4) {
                    ForEach(enabledAgents) { agent in
                        let isRunning = processMonitor.runningAgentNames.contains(agent.name)
                        HStack {
                            Circle()
                                .fill(isRunning ? Color.green : Color.gray.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text(agent.name)
                                .font(.system(size: 12, weight: isRunning ? .medium : .regular))
                                .foregroundColor(isRunning ? .primary : .secondary)
                            Spacer()
                            if isRunning {
                                Text("Running")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
    }
}
