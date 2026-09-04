//
//  ThermalMonitor.swift
//  Awake
//

import Foundation
import Combine
import IOKit

@MainActor
public final class ThermalMonitor: ObservableObject {
    public static let shared = ThermalMonitor()

    @Published public private(set) var thermalReading: ThermalReading = ThermalReading()

    private var timer: Timer?

    private init() {
        updateThermalState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    @objc private func thermalStateChanged() {
        updateThermalState()
    }

    public func startMonitoring() {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                ThermalMonitor.shared.updateThermalState()
            }
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    public func updateThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        let temp = readCurrentTemperature()

        self.thermalReading = ThermalReading(
            temperatureCelsius: temp,
            thermalState: state
        )
    }

    /// Reads temperature from IOKit PMU temperature sensors or AppleSMC
    private func readCurrentTemperature() -> Double? {
        // Query AppleARMPMUTempSensor or AppleSMC temperature sensors in IORegistry
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleARMPMUTempSensor")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var temps: [Double] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let tempNumber = IORegistryEntryCreateCFProperty(
                service,
                "temperature" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? NSNumber {
                let tempVal = tempNumber.doubleValue
                if tempVal > 10.0 && tempVal < 120.0 {
                    temps.append(tempVal)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        if !temps.isEmpty {
            // Return highest or average temperature
            return temps.max()
        }

        return nil
    }
}
