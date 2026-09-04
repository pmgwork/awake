//
//  LidMonitor.swift
//  Awake
//

import Foundation
import Combine
import IOKit
import IOKit.pwr_mgt

@MainActor
public final class LidMonitor: ObservableObject {
    public static let shared = LidMonitor()

    @Published public private(set) var isLidClosed: Bool = false
    @Published public private(set) var lidState: LidState = .open

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
            self.lidState = .unknown
            self.isLidClosed = false
            return
        }
        defer { IOObjectRelease(rootDomain) }

        if let property = IORegistryEntryCreateCFProperty(
            rootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool {
            self.isLidClosed = property
            self.lidState = property ? .closed : .open
        } else {
            // Desktops (Mac Studio / Mac mini / iMac / Mac Pro) do not have AppleClamshellState
            self.isLidClosed = false
            self.lidState = .open
        }
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

    public func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}
