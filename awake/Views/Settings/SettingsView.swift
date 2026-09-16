//
//  SettingsView.swift
//  Awake
//

import SwiftUI

/// The panes of the settings window. AppKit presents them as selectable
/// toolbar items while each pane remains implemented in SwiftUI.
enum SettingsTab: CaseIterable {
    case general
    case sessions
    case agents
    case cooling

    var title: String {
        switch self {
        case .general: return L10n.string("General")
        case .sessions: return L10n.string("Sessions")
        case .agents: return L10n.string("Agents")
        case .cooling: return L10n.string("Cooling")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .sessions: return "display"
        case .agents: return "cpu"
        case .cooling: return "wind"
        }
    }

    var toolbarImage: NSImage? {
        NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
    }

    static let contentWidth: CGFloat = 540
}
