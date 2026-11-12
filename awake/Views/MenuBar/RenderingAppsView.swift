//
//  RenderingAppsView.swift
//  Awake
//

import SwiftUI

/// Lists only the apps that are rendering; hidden while none is.
struct RenderingAppsView: View {
    @ObservedObject var monitor: RenderMonitor

    var body: some View {
        let rendering = RenderApp.allCases.filter(monitor.renderingApps.contains)
        if !rendering.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                RunningListHeader(title: "Rendering Apps",
                                  count: L10n.format("%d rendering", rendering.count))

                ChipFlowLayout(spacing: 6) {
                    ForEach(rendering) { app in
                        RunningChip(title: app.displayName)
                    }
                }
            }
        }
    }
}
