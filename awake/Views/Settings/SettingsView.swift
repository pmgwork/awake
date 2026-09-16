//
//  SettingsView.swift
//  Awake
//

import SwiftUI

/// The panes of the settings window. An `NSTabViewController` presents them so
/// the system draws the standard settings toolbar (see
/// `SettingsWindowController`).
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

    /// The image shown in the settings toolbar.
    var toolbarImage: NSImage? {
        NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
    }

    /// The width shared by every pane. Heights come from measuring each pane.
    static let contentWidth: CGFloat = 540
}
