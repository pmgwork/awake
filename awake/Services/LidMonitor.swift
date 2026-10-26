//
//  LidMonitor.swift
//  Awake
//

import Foundation
import Combine
import IOKit

@MainActor
public final class LidMonitor: ObservableObject {
    public static let shared = LidMonitor()

    @Published public private(set) var isLidClosed: Bool = false

    private var notifyPort: IONotificationPortRef?
    private var notificationObject: io_object_t = 0
    private var pollingTimer: Timer?

    private init() {
        checkLidState()
        setupIOKitNotification()
        startPolling()
    }

    deinit {
        pollingTimer?.invalidate()
        if notificationObject != 0 {
            IOObjectRelease(notificationObject)
        }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
        }
    }

    public func checkLidState() {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else {
            setLidClosed(false)
            return
        }
        defer { IOObjectRelease(rootDomain) }

        if let property = IORegistryEntryCreateCFProperty(
            rootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool {
            setLidClosed(property)
        } else {
            // Desktops (Mac Studio / Mac mini / iMac / Mac Pro) do not have AppleClamshellState
            setLidClosed(false)
        }
    }

    // @Published fires on every assignment, and this runs on a 1 Hz poll.
    private func setLidClosed(_ closed: Bool) {
        guard isLidClosed != closed else { return }
        isLidClosed = closed
    }

    private func setupIOKitNotification() {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return }

        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notifyPort else {
            IOObjectRelease(rootDomain)
            return
        }

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let callback: IOServiceInterestCallback = { (refcon, service, messageType, messageArgument) in
            Task { @MainActor in
                LidMonitor.shared.checkLidState()
            }
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let kr = IOServiceAddInterestNotification(
            port,
            rootDomain,
            kIOGeneralInterest,
            callback,
            selfPtr,
            &notificationObject
        )

        if kr != kIOReturnSuccess {
            NSLog("[LidMonitor] Failed to add IOKit interest notification: %d", kr)
        }
        IOObjectRelease(rootDomain)
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                LidMonitor.shared.checkLidState()
            }
        }
    }
}
