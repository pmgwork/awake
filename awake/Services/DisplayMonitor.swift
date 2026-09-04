//
//  DisplayMonitor.swift
//  Awake
//

import Foundation
import Combine
import CoreGraphics
import AppKit

@MainActor
public final class DisplayMonitor: ObservableObject {
    public static let shared = DisplayMonitor()

    @Published public private(set) var hasExternalDisplay: Bool = false
    @Published public private(set) var displayCount: Int = 1
    @Published public private(set) var displayState: DisplayState = DisplayState()

    private var pollingTimer: Timer?

    private init() {
        updateDisplayInfo()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        startPolling()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    @objc private func screenParametersChanged() {
        updateDisplayInfo()
    }

    public func updateDisplayInfo() {
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        let result = CGGetOnlineDisplayList(16, &onlineDisplays, &displayCount)
        guard result == .success else {
            self.hasExternalDisplay = false
            self.displayCount = NSScreen.screens.count
            self.displayState = DisplayState(displayCount: self.displayCount, hasExternalDisplay: false)
            return
        }

        var foundExternal = false
        var activeDisplays = 0

        for i in 0..<Int(displayCount) {
            let dID = onlineDisplays[i]
            if CGDisplayIsActive(dID) != 0 || CGDisplayIsOnline(dID) != 0 {
                activeDisplays += 1
                if CGDisplayIsBuiltin(dID) == 0 {
                    foundExternal = true
                }
            }
        }

        let totalDisplays = max(activeDisplays, NSScreen.screens.count)

        self.hasExternalDisplay = foundExternal
        self.displayCount = totalDisplays
        self.displayState = DisplayState(
            displayCount: totalDisplays,
            hasExternalDisplay: foundExternal,
            isBuiltinDisplayActive: true
        )
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                DisplayMonitor.shared.updateDisplayInfo()
            }
        }
    }
}
