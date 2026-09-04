//
//  AgentSettingsView.swift
//  Awake
//

import SwiftUI

struct AgentSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var processMonitor: ProcessMonitor

    @State private var showingAddSheet: Bool = false
    @State private var newAgentName: String = ""
    @State private var newProcessNames: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Monitored AI Agents")
                    .font(.headline)
                Text("Select which AI Agent CLI processes will automatically keep your Mac awake while running.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Agents List
            List {
                Section(header: Text("Preset Agents")) {
                    ForEach(settings.monitoredAgents.filter { $0.isPreset }) { agent in
                        agentRow(agent: agent)
                    }
                }

                let customAgents = settings.monitoredAgents.filter { !$0.isPreset }
                Section(header: Text("Custom Agents")) {
                    if customAgents.isEmpty {
                        Text("No custom agents added.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(customAgents) { agent in
                            agentRow(agent: agent, canDelete: true)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(height: 220)

            // Add Custom Process Button
            HStack {
                Button(action: {
                    showingAddSheet = true
                }) {
                    Label("Add Process...", systemImage: "plus")
                }

                Spacer()

                Button("Reset to Presets") {
                    settings.resetToDefaults()
                }
                .foregroundColor(.secondary)
            }

            Divider()

            // Live Process Detector Preview
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Live Process Detection Preview")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        processMonitor.scanNow()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                if processMonitor.runningAgentNames.isEmpty {
                    Text("No monitored agent processes currently detected running.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(processMonitor.runningAgentNames).sorted(), id: \.self) { name in
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(name)
                                .font(.caption.weight(.medium))
                            if let pids = processMonitor.activeProcesses[name] {
                                Text("PID: \(pids.map { "\($0)" }.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .sheet(isPresented: $showingAddSheet) {
            addCustomAgentSheet
        }
    }

    private func agentRow(agent: MonitoredAgent, canDelete: Bool = false) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { agent.isEnabled },
                set: { _ in settings.toggleAgent(id: agent.id) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(agent.processNames.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Spacer()

            if canDelete {
                Button(action: {
                    settings.deleteAgent(id: agent.id)
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private var addCustomAgentSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Monitored Agent")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Agent Display Name:")
                    .font(.caption.bold())
                TextField("e.g. My Custom Agent", text: $newAgentName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Executable Process Names (comma separated):")
                    .font(.caption.bold())
                TextField("e.g. my-agent, custom-cli", text: $newProcessNames)
                    .textFieldStyle(.roundedBorder)
                Text("Matches the command name or path basename in Terminal/CLI.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showingAddSheet = false
                    newAgentName = ""
                    newProcessNames = ""
                }
                Button("Add") {
                    let names = newProcessNames.split(separator: ",").map { String($0) }
                    settings.addCustomAgent(name: newAgentName, processNames: names)
                    showingAddSheet = false
                    newAgentName = ""
                    newProcessNames = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newAgentName.trimmingCharacters(in: .whitespaces).isEmpty || newProcessNames.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
