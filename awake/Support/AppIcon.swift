//
//  AppIcon.swift
//  Awake
//

import AppKit

enum AppIcon {
    /// The app icon, resized for use inside the interface.
    static func image(size: CGFloat) -> NSImage? {
        guard let icon = NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage else {
            return nil
        }
        let targetSize = NSSize(width: size, height: size)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        icon.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: icon.size),
            operation: .sourceOver,
            fraction: 1
        )
        resized.unlockFocus()
        resized.size = targetSize
        return resized
    }
}
