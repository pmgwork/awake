//
//  SettingsView.swift
//  Awake
//

import SwiftUI

/// The panes of the settings window. AppKit presents them as selectable
/// toolbar items while each pane remains implemented in SwiftUI.
enum SettingsTab: String, CaseIterable {
    case general
    case keepAwake
    case monitoring
    case cooling
    case permissions

    var title: String {
        switch self {
        case .general: return L10n.string("General")
        case .keepAwake: return L10n.string("Keep Awake")
        case .monitoring: return L10n.string("Monitor")
        case .cooling: return L10n.string("Cooling")
        case .permissions: return L10n.string("Permissions")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .keepAwake: return "cup.and.saucer"
        case .monitoring: return "eye"
        case .cooling: return "wind"
        case .permissions: return "lock.shield"
        }
    }

    var toolbarImage: NSImage? {
        NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
    }

    static let contentWidth: CGFloat = 540
}
