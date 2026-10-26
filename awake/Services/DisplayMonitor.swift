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
            setHasExternalDisplay(false)
            return
        }

        var foundExternal = false

        for i in 0..<Int(displayCount) {
            let dID = onlineDisplays[i]
            if CGDisplayIsActive(dID) != 0 || CGDisplayIsOnline(dID) != 0 {
                if CGDisplayIsBuiltin(dID) == 0 {
                    foundExternal = true
                }
            }
        }

        setHasExternalDisplay(foundExternal)
    }

    // @Published fires on every assignment, and this runs on a 2 s poll.
    private func setHasExternalDisplay(_ value: Bool) {
        guard hasExternalDisplay != value else { return }
        hasExternalDisplay = value
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                DisplayMonitor.shared.updateDisplayInfo()
            }
        }
    }
}
