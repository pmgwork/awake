//
//  RenderMonitor.swift
//  Awake
//

import Foundation
import Combine
import Darwin

/// Detects rendering in Blender, Adobe After Effects, Media Encoder and Houdini, only
/// while the condition is enabled.
///
/// - Dedicated render processes (aerender, husk, mantra, `blender -b -f/-a`)
///   count as rendering while they run.
/// - Renders started in the Blender window are reported by a startup script
///   that Awake installs into Blender (see `BlenderRenderIntegration`).
/// - Linked Adobe After Effects sessions report render queue item transitions.
/// AME alone uses sustained per-process CPU/GPU load as a heuristic.
@MainActor
public final class RenderMonitor: ObservableObject {
    public static let shared = RenderMonitor()

    @Published public private(set) var renderingApps: Set<RenderApp> = []
    public var isRendering: Bool { !renderingApps.isEmpty }
    /// Apps turned on in Settings → Monitoring.
    public private(set) var enabledApps = Set(RenderApp.allCases)

    nonisolated static let sampleInterval: TimeInterval = 3

    private var timer: Timer?
    private var detectors: [RenderApp: RenderActivityDetector] = [:]
    private let queue = DispatchQueue(label: "pmgwork.awake.render-monitor", qos: .utility)
    private var generation = 0
    private var previousAMELoad: AMELoadSampler.Sample?
    private var ameDetector = AMELoadDetector()

    public func startMonitoring() {
        guard timer == nil else { return }
        generation += 1
        timer = Timer.scheduledTimer(withTimeInterval: Self.sampleInterval, repeats: true) { _ in
            Task { @MainActor in RenderMonitor.shared.sample() }
        }
        AfterEffectsRenderIntegration.shared.setEnabled(enabledApps.contains(.afterEffects))
        sample()
    }

    public func updateEnabledApps(_ apps: Set<RenderApp>) {
        // A saved preference alone must not start monitoring before the
        // user has linked Blender. Existing linked installations keep it.
        let apps = BlenderRenderIntegration.status() == .linked ? apps : apps.subtracting([.blender])
        guard enabledApps != apps else { return }
        enabledApps = apps
        AfterEffectsRenderIntegration.shared.setEnabled(timer != nil && apps.contains(.afterEffects))
        previousAMELoad = nil
        ameDetector = AMELoadDetector()
        detectors = detectors.filter { apps.contains($0.key) }
        let rendering = renderingApps.intersection(apps)
        if renderingApps != rendering { renderingApps = rendering }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        AfterEffectsRenderIntegration.shared.setEnabled(false)
        generation += 1
        previousAMELoad = nil
        ameDetector = AMELoadDetector()
        detectors = [:]
        if !renderingApps.isEmpty { renderingApps = [] }
    }

    private func sample() {
        AfterEffectsRenderIntegration.shared.refresh()
        let aeRendering = enabledApps.contains(.afterEffects) && AfterEffectsRenderIntegration.shared.hasActiveRender
        let generation = self.generation
        let includeAME = enabledApps.contains(.mediaEncoder)
        queue.async {
            let sample = RenderProcessSampler.sample(includeAME: includeAME)
            Task { @MainActor in
                let monitor = RenderMonitor.shared
                guard monitor.generation == generation else { return }
                var rendering: Set<RenderApp> = []
                for app in RenderApp.allCases where monitor.enabledApps.contains(app) {
                    var detector = monitor.detectors[app] ?? RenderActivityDetector()
                    if detector.update(signaled: sample.signaledApps.contains(app) || (app == .afterEffects && aeRendering),
                                       now: sample.date) {
                        rendering.insert(app)
                    }
                    monitor.detectors[app] = detector
                }
                if monitor.enabledApps.contains(.mediaEncoder), let ame = sample.ameLoad {
                    if ame.isRunning, let previous = monitor.previousAMELoad, let load = ame.load(since: previous) {
                        if monitor.ameDetector.update(cpu: load.cpu, gpu: load.gpu, now: ame.uptime) {
                            rendering.insert(.mediaEncoder)
                        }
                    } else {
                        monitor.ameDetector = AMELoadDetector()
                    }
                    monitor.previousAMELoad = ame
                }
                if monitor.renderingApps != rendering { monitor.renderingApps = rendering }
            }
        }
    }
}

/// Explicit export signals start cooling immediately. A short grace period
/// bridges the gaps between frames or consecutive render jobs.
nonisolated struct RenderActivityDetector {
    static let signalStopDelay: TimeInterval = 10
    private var lastSignal: Date?

    mutating func update(signaled: Bool, now: Date) -> Bool {
        if signaled { lastSignal = now }
        return lastSignal.map { now.timeIntervalSince($0) < Self.signalStopDelay } ?? false
    }
}

public enum RenderApp: String, CaseIterable, Identifiable, Sendable {
    case blender, afterEffects, mediaEncoder, houdini

    public var id: String { rawValue }

    /// Product names, which are not translated.
    public var displayName: String {
        switch self {
        case .blender: return "Blender"
        case .afterEffects: return "Adobe After Effects"
        case .mediaEncoder: return "Adobe Media Encoder"
        case .houdini: return "Houdini"
        }
    }
}

nonisolated enum RenderProcessSampler {
    /// Lowercased executable names of processes that exist only to render.
    static let rendererNames: [String: RenderApp] = [
        "aerender": .afterEffects, "husk": .houdini, "mantra": .houdini,
    ]

    static let blenderRenderOptions: Set<String> = ["-f", "--render-frame", "-a", "--render-anim"]

    struct Sample {
        let date: Date
        /// Apps with a running render process or a Blender script report.
        let signaledApps: Set<RenderApp>
        let ameLoad: AMELoadSampler.Sample?
    }

    /// `arguments` is read only for Blender, whose window and command-line
    /// renders share one executable.
    static func match(executablePath: String, arguments: () -> [String]?) -> RenderApp? {
        let name = (executablePath as NSString).lastPathComponent.lowercased()
        if let app = rendererNames[name] { return app }
        if name == "blender" {
            return arguments().map(isBlenderCommandLineRender) == true
                ? .blender : nil
        }
        return nil
    }

    static func isBlenderCommandLineRender(_ arguments: [String]) -> Bool {
        (arguments.contains("-b") || arguments.contains("--background"))
            && arguments.contains(where: blenderRenderOptions.contains)
    }

    static func sample(now: Date = Date(), includeAME: Bool = false) -> Sample {
        var signaled: Set<RenderApp> = []
        if BlenderRenderIntegration.hasActiveRender(isBlender: { pid in
            executablePath(of: pid).map { ($0 as NSString).lastPathComponent.lowercased() == "blender" } ?? false
        }) {
            signaled.insert(.blender)
        }
        var ameRoots: Set<pid_t> = []
        for pid in allProcessIDs() {
            guard let path = executablePath(of: pid) else { continue }
            if includeAME && AMELoadSampler.isMediaEncoder(executablePath: path) { ameRoots.insert(pid) }
            if let app = match(executablePath: path, arguments: { arguments(of: pid) }) { signaled.insert(app) }
        }
        return Sample(date: now, signaledApps: signaled, ameLoad: includeAME ? AMELoadSampler.sample(roots: ameRoots) : nil)
    }

    private static func allProcessIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return Array(pids.prefix(Int(filled))).filter { $0 > 0 }
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Command-line arguments of a process owned by the same user.
    private static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // The executable path comes first, padded with NUL bytes.
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < Int(argc) && index < size {
            let start = index
            while index < size && buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

}
