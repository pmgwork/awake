//
//  AMELoadMonitor.swift
//  Awake
//

import Foundation
import Darwin
import IOKit

/// Only AME uses this heuristic. The other render apps use explicit signals.
nonisolated struct AMELoadDetector {
    static let startCPU = 1.0 // One fully used CPU core.
    static let stopCPU = 0.5
    static let startGPU = 0.2 // Driver-reported GPU seconds per elapsed second.
    static let stopGPU = 0.1
    static let startDelay: TimeInterval = 10
    static let stopDelay: TimeInterval = 30

    private(set) var isActive = false
    private var crossingSince: TimeInterval?

    mutating func update(cpu: Double, gpu: Double, now: TimeInterval) -> Bool {
        let crossing = isActive ? cpu < Self.stopCPU && gpu < Self.stopGPU
            : cpu >= Self.startCPU || gpu >= Self.startGPU
        guard crossing else { crossingSince = nil; return isActive }
        let since = crossingSince ?? now
        crossingSince = since
        if now - since >= (isActive ? Self.stopDelay : Self.startDelay) {
            isActive.toggle()
            crossingSince = nil
        }
        return isActive
    }
}

nonisolated enum AMELoadSampler {
    struct CPUCounter {
        let start: UInt64
        let seconds: Double
    }

    struct GPUCounter {
        let pid: pid_t
        let nanoseconds: [Double]
    }

    struct Sample {
        let uptime: TimeInterval
        let isRunning: Bool
        let cpu: [pid_t: CPUCounter]
        let gpu: [UInt64: GPUCounter]

        /// New processes/clients and counter resets establish a baseline.
        /// A long sampling gap also resets the detector after sleep or stalls.
        func load(since previous: Sample) -> (cpu: Double, gpu: Double)? {
            let elapsed = uptime - previous.uptime
            guard elapsed > 0, elapsed <= 10 else { return nil }
            let cpuSeconds = cpu.reduce(0.0) { total, entry in
                guard let old = previous.cpu[entry.key], old.start == entry.value.start else { return total }
                return total + max(0, entry.value.seconds - old.seconds)
            }
            let gpuNanoseconds = gpu.reduce(0.0) { total, entry in
                guard let old = previous.gpu[entry.key], old.pid == entry.value.pid,
                      old.nanoseconds.count == entry.value.nanoseconds.count else { return total }
                return total + zip(entry.value.nanoseconds, old.nanoseconds).reduce(0.0) {
                    $0 + max(0, $1.0 - $1.1)
                }
            }
            return (cpuSeconds / elapsed, gpuNanoseconds / 1_000_000_000 / elapsed)
        }
    }

    static func isMediaEncoder(executablePath: String) -> Bool {
        let executable = URL(fileURLWithPath: executablePath)
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return executable.lastPathComponent.hasPrefix("Adobe Media Encoder")
            && executable.deletingLastPathComponent().lastPathComponent == "MacOS"
            && app.pathExtension == "app" && app.lastPathComponent.hasPrefix("Adobe Media Encoder")
    }

    static func sample(roots: Set<pid_t>) -> Sample {
        var pids = roots
        var pending = Array(roots)
        while let pid = pending.popLast() {
            for child in children(of: pid) where pids.insert(child).inserted { pending.append(child) }
        }
        var cpu: [pid_t: CPUCounter] = [:]
        for pid in pids {
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            if result == 0 {
                cpu[pid] = CPUCounter(start: info.ri_proc_start_abstime,
                    seconds: (Double(info.ri_user_time) + Double(info.ri_system_time)) * secondsPerTick)
            }
        }
        return Sample(uptime: ProcessInfo.processInfo.systemUptime, isRunning: !roots.isEmpty,
                      cpu: cpu, gpu: pids.isEmpty ? [:] : gpuCounters(pids: pids))
    }

    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    private static func children(of pid: pid_t) -> [pid_t] {
        let size = proc_listchildpids(pid, nil, 0)
        guard size > 0 else { return [] }
        var children = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.size + 16)
        let capacity = Int32(children.count * MemoryLayout<pid_t>.size)
        let written = proc_listchildpids(pid, &children, capacity)
        guard written > 0 else { return [] }
        return Array(children.prefix(Int(written) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }
    }

    /// Driver-specific counters are optional. Never substitute device-wide
    /// utilization: another application's work must not activate AME cooling.
    private static func gpuCounters(pids: Set<pid_t>) -> [UInt64: GPUCounter] {
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(accelerators) }
        var result: [UInt64: GPUCounter] = [:]
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var clients: io_iterator_t = 0
            guard IORegistryEntryCreateIterator(accelerator, kIOServicePlane, UInt32(kIORegistryIterateRecursively), &clients) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(clients) }
            while case let client = IOIteratorNext(clients), client != 0 {
                defer { IOObjectRelease(client) }
                guard let creator = property(client, "IOUserClientCreator") as? String,
                      let pid = creatorPID(creator), pids.contains(pid) else { continue }
                let values: [Double]
                if let total = property(client, "accumulatedGPUTime") as? NSNumber {
                    values = [total.doubleValue]
                } else if let usage = property(client, "AppUsage") as? [[String: Any]] {
                    values = usage.compactMap { ($0["accumulatedGPUTime"] as? NSNumber)?.doubleValue }
                } else { continue }
                var identifier: UInt64 = 0
                if !values.isEmpty && IORegistryEntryGetRegistryEntryID(client, &identifier) == KERN_SUCCESS {
                    result[identifier] = GPUCounter(pid: pid, nanoseconds: values)
                }
            }
        }
        return result
    }

    static func creatorPID(_ creator: String) -> pid_t? {
        guard creator.hasPrefix("pid "), let end = creator.firstIndex(of: ",") else { return nil }
        return pid_t(creator[creator.index(creator.startIndex, offsetBy: 4)..<end])
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
