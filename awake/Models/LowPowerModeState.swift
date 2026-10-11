//
//  LowPowerModeState.swift
//  Awake
//

import Foundation

/// The Low Power Mode setting of each power source, as `pmset -g custom`
/// reports it. `nil` means the Mac has no such power source.
nonisolated struct LowPowerModeState: Codable, Equatable, Sendable {
    /// "lowpowermode", or "powermode" on Macs that also offer High Power Mode.
    /// In both, 1 means Low Power Mode.
    var key: String
    var battery: Int?
    var ac: Int?

    static let supportedKeys = ["lowpowermode", "powermode"]
    static let lowPowerValue = 1

    var isLowPowerEverywhere: Bool {
        [battery, ac].allSatisfy { $0 == nil || $0 == Self.lowPowerValue }
    }

    /// Arguments for the helper's `hold-lowpower` and `set-lowpower`
    /// commands: the key, then the battery and AC values ("-" leaves a
    /// source unchanged).
    var helperArguments: [String] {
        [key, battery.map(String.init) ?? "-", ac.map(String.init) ?? "-"]
    }

    /// The part of this saved state that still needs restoring: only the
    /// sources that are still in the Low Power Mode Awake turned on, so a
    /// change the user made in the meantime is kept. `nil` when nothing needs
    /// restoring.
    func restoration(from current: LowPowerModeState) -> LowPowerModeState? {
        guard current.key == key else { return nil }
        func restored(_ saved: Int?, _ now: Int?) -> Int? {
            guard let saved, saved != Self.lowPowerValue, now == Self.lowPowerValue else { return nil }
            return saved
        }
        let restoration = LowPowerModeState(
            key: key,
            battery: restored(battery, current.battery),
            ac: restored(ac, current.ac)
        )
        return restoration.battery == nil && restoration.ac == nil ? nil : restoration
    }

    static func parse(pmsetCustomOutput output: String) -> LowPowerModeState? {
        enum Source { case battery, ac }
        var section: Source?
        var values: [String: [Source: Int]] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":") {
                switch trimmed {
                case "Battery Power:": section = .battery
                case "AC Power:": section = .ac
                default: section = nil
                }
                continue
            }
            let fields = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let section, fields.count == 2, supportedKeys.contains(fields[0]),
                  let value = Int(fields[1]), (0...2).contains(value) else { continue }
            values[fields[0], default: [:]][section] = value
        }
        for key in supportedKeys {
            if let found = values[key], !found.isEmpty {
                return LowPowerModeState(key: key, battery: found[.battery], ac: found[.ac])
            }
        }
        return nil
    }

    /// Reads the current setting. `pmset -g` needs no privileges.
    static func readCurrent() async -> LowPowerModeState? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "custom"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return nil
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return LowPowerModeState.parse(pmsetCustomOutput: String(decoding: data, as: UTF8.self))
        }.value
    }
}
