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
                Text(L10n.string("Monitored Agents"))
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
                Text(L10n.string("No agents are being monitored. Turn them on in Settings."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            } else {
                AgentChipFlowLayout(spacing: 6) {
                    ForEach(enabledAgents) { agent in
                        let provider = agent.provider!
                        let sessionCount = eventMonitor.activeSessionCountByProvider[provider, default: 0]
                        let isRunning = sessionCount > 0
                        let integrationStatus = integrationManager.status(for: provider)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isRunning ? Color.green : integrationStatus == .linked ? Color.gray.opacity(0.5) : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(agent.name)
                                .font(.system(size: 11, weight: isRunning ? .medium : .regular))
                                .foregroundColor(isRunning ? .primary : .secondary)
                            if sessionCount > 1 {
                                Text("×\(sessionCount)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .help(integrationStatus == .linked
                              ? (isRunning ? L10n.string("Running") : integrationStatus.label)
                              : integrationStatus.label)
                    }
                }
            }
        }
    }
}

/// Lays chips out left to right and wraps to the next line when the row is full.
private struct AgentChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
