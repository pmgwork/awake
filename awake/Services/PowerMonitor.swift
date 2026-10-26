//
//  PowerMonitor.swift
//  Awake
//

import Foundation
import Combine
import IOKit.ps

@MainActor
public final class PowerMonitor: ObservableObject {
    public static let shared = PowerMonitor()

    @Published public private(set) var isOnACPower: Bool = true
    @Published public private(set) var batteryLevel: Int? = nil

    private var runLoopSource: CFRunLoopSource?
    private var pollingTimer: Timer?

    private init() {
        updatePowerState()
        setupPowerNotification()
        startPolling()
    }

    deinit {
        pollingTimer?.invalidate()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    public func updatePowerState() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            // Desktops without battery default to AC
            apply(isOnACPower: true, batteryLevel: nil)
            return
        }

        var isAC = true
        var batteryPct: Int? = nil

        for item in list {
            if let desc = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any] {
                if let powerSourceState = desc[kIOPSPowerSourceStateKey as String] as? String {
                    isAC = (powerSourceState == (kIOPSACPowerValue as String))
                }
                if let currentCapacity = desc[kIOPSCurrentCapacityKey as String] as? Int,
                   let maxCapacity = desc[kIOPSMaxCapacityKey as String] as? Int,
                   maxCapacity > 0 {
                    batteryPct = Int((Double(currentCapacity) / Double(maxCapacity)) * 100.0)
                }
            }
        }

        apply(isOnACPower: isAC, batteryLevel: batteryPct)
    }

    // @Published fires on every assignment, and this runs on a 3 s poll.
    private func apply(isOnACPower: Bool, batteryLevel: Int?) {
        if self.isOnACPower != isOnACPower { self.isOnACPower = isOnACPower }
        if self.batteryLevel != batteryLevel { self.batteryLevel = batteryLevel }
    }

    private func setupPowerNotification() {
        let callback: IOPowerSourceCallbackType = { _ in
            Task { @MainActor in
                PowerMonitor.shared.updatePowerState()
            }
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                PowerMonitor.shared.updatePowerState()
            }
        }
    }
}
