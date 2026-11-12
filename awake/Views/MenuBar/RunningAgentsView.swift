//
//  RunningAgentsView.swift
//  Awake
//

import SwiftUI

/// Lists only the agents that are running; hidden while none is.
struct RunningAgentsView: View {
    @ObservedObject var eventMonitor: AgentEventMonitor
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let running = settings.monitoredAgents.compactMap { agent -> (MonitoredAgent, Int)? in
            guard agent.isEnabled, let provider = agent.provider else { return nil }
            let count = eventMonitor.activeSessionCountByProvider[provider, default: 0]
            return count > 0 ? (agent, count) : nil
        }
        .sorted { $0.0.provider!.sortIndex < $1.0.provider!.sortIndex }
        if !running.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                RunningListHeader(title: "Running Agents",
                                  count: L10n.format("%d running", eventMonitor.activeSessionCount))

                ChipFlowLayout(spacing: 6) {
                    ForEach(running, id: \.0.id) { agent, sessionCount in
                        RunningChip(title: agent.name, count: sessionCount)
                    }
                }
            }
        }
    }
}

struct RunningListHeader: View {
    let title: String
    let count: String

    var body: some View {
        HStack {
            Text(L10n.string(title))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
            Text(count)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.green)
        }
    }
}

struct RunningChip: View {
    let title: String
    var count = 1

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
            if count > 1 {
                Text("×\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// Lays chips out left to right and wraps to the next line when the row is full.
struct ChipFlowLayout: Layout {
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
