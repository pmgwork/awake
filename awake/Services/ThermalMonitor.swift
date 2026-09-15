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
    private var registrySensorsAvailable = true

    /// SMC temperature keys used as a fallback. Key names differ between
    /// chips, so candidates are filtered down to the ones this Mac exposes.
    private static let smcTemperatureKeys: [String] = [
        // Apple Silicon CPU cores (current naming)
        "Tp04", "Tp05", "Tp06", "Tp0a", "Tp0b", "Tp0c", "Tp0g", "Tp0h", "Tp0i",
        "Tp0m", "Tp0n", "Tp0o", "Tp0u", "Tp0v", "Tp10", "Tp16", "Tp17", "Tp18",
        // Apple Silicon CPU cores (older naming)
        "Tp01", "Tp09", "Tp0D", "Tp0f", "Tp0j", "Tp0l", "Tp0P", "Tp0T",
        // Intel CPU proximity and diode
        "TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "TC0c",
    ]

    private lazy var availableSMCTemperatureKeys: [String] = {
        let client = SMCClient.shared
        return Self.smcTemperatureKeys.filter { client.getKeyInfo(key: $0) != nil }
    }()

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
        // macOS 27 no longer exposes a `temperature` property on the
        // AppleARMPMUTempSensor IORegistry sensors. Remember when the registry
        // path stops producing values and use AppleSMC from then on.
        if registrySensorsAvailable {
            if let registryTemperature = readRegistryTemperature() {
                return registryTemperature
            }
            registrySensorsAvailable = false
        }

        return readSMCTemperature()
    }

    private func readRegistryTemperature() -> Double? {
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

    /// Reads the hottest CPU sensor through AppleSMC.
    private func readSMCTemperature() -> Double? {
        let client = SMCClient.shared
        let temps: [Double] = availableSMCTemperatureKeys.compactMap { key in
            guard let value = client.readFloat(key: key) else { return nil }
            let temperature = Double(value)
            // Some `Tp`-family keys report power or offsets instead of a
            // temperature, so keep the same plausibility window the IORegistry
            // path used.
            guard temperature > 10.0 && temperature < 120.0 else { return nil }
            return temperature
        }

        return temps.max()
    }
}
