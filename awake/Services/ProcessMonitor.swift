//
//  ProcessMonitor.swift
//  Awake
//

import Foundation
import Combine
import Darwin

/// Agent backends are often long-lived, so process existence alone cannot tell us
/// whether an agent is actually working. This detector samples cumulative CPU
/// time for each agent and all of its descendants and keeps a short activity hold
/// so brief network waits do not cause the awake assertion to flap.
private nonisolated final class AgentActivityDetector: @unchecked Sendable {
    static let shared = AgentActivityDetector()

    private struct ActivityState {
        var previousCPUTimeByPID: [pid_t: UInt64] = [:]
        var previousSampleUptime: TimeInterval?
        var lastActivityUptime: TimeInterval?
    }

    private let lock = NSLock()
    private var states: [UUID: ActivityState] = [:]

    private let minimumBusyCPUPercent = 0.1
    private let activityHoldSeconds: TimeInterval = 60

    private init() {}

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        states = [:]
    }

    func isActive(agentID: UUID, rootPIDs: Set<pid_t>, parentByPID: [pid_t: pid_t]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !rootPIDs.isEmpty else {
            states.removeValue(forKey: agentID)
            return false
        }

        var state = states[agentID] ?? ActivityState()

        var observedPIDs = rootPIDs
        var addedDescendant = true
        while addedDescendant {
            addedDescendant = false
            for (pid, parentPID) in parentByPID where observedPIDs.contains(parentPID) && !observedPIDs.contains(pid) {
                observedPIDs.insert(pid)
                addedDescendant = true
            }
        }

        let now = ProcessInfo.processInfo.systemUptime
        var currentCPUTimeByPID: [pid_t: UInt64] = [:]
        for pid in observedPIDs {
            if let cpuTime = Self.cumulativeCPUTime(pid: pid) {
                currentCPUTimeByPID[pid] = cpuTime
            }
        }

        if let previousSampleUptime = state.previousSampleUptime {
            let elapsed = now - previousSampleUptime
            if elapsed > 0 {
                var cpuTimeDelta: UInt64 = 0
                for (pid, currentCPUTime) in currentCPUTimeByPID {
                    guard let previousCPUTime = state.previousCPUTimeByPID[pid], currentCPUTime >= previousCPUTime else {
                        continue
                    }
                    cpuTimeDelta &+= currentCPUTime - previousCPUTime
                }

                let cpuPercent = (Double(cpuTimeDelta) / 1_000_000_000.0) / elapsed * 100.0
                let newDescendantStarted = currentCPUTimeByPID.keys.contains {
                    !rootPIDs.contains($0) && state.previousCPUTimeByPID[$0] == nil
                }
                if cpuPercent >= minimumBusyCPUPercent || newDescendantStarted {
                    state.lastActivityUptime = now
                }
            }
        }

        state.previousCPUTimeByPID = currentCPUTimeByPID
        state.previousSampleUptime = now
        states[agentID] = state
        return state.lastActivityUptime.map { now - $0 <= activityHoldSeconds } ?? false
    }

    private static func cumulativeCPUTime(pid: pid_t) -> UInt64? {
        var taskInfo = proc_taskinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let actualSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, expectedSize)
        guard actualSize == expectedSize else { return nil }
        return taskInfo.pti_total_user &+ taskInfo.pti_total_system
    }
}

@MainActor
public final class ProcessMonitor: ObservableObject {
    public static let shared = ProcessMonitor()

    @Published public private(set) var runningAgentNames: Set<String> = []
    @Published public private(set) var runningAgentCount: Int = 0
    @Published public private(set) var hasRunningAgent: Bool = false
    @Published public private(set) var activeProcesses: [String: [pid_t]] = [:]

    private var timer: Timer?
    private let scanQueue = DispatchQueue(label: "pmgwork.awake.processmonitor", qos: .utility)
    private var monitoredAgents: [MonitoredAgent] = []
    private nonisolated static let activityAwareProcessNames: Set<String> = [
        "codex", "agy", "claude", "opencode", "opencode2",
    ]

    private init() {
        startScanning()
    }

    deinit {
        timer?.invalidate()
    }

    public func updateMonitoredAgents(_ agents: [MonitoredAgent]) {
        self.monitoredAgents = agents
        scanQueue.async {
            ProcessMonitor.performScan(agents: agents)
        }
    }

    public func startScanning() {
        stopScanning()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                let agents = ProcessMonitor.shared.monitoredAgents
                ProcessMonitor.shared.scanQueue.async {
                    ProcessMonitor.performScan(agents: agents)
                }
            }
        }
        let agents = self.monitoredAgents
        scanQueue.async {
            ProcessMonitor.performScan(agents: agents)
        }
    }

    public func stopScanning() {
        timer?.invalidate()
        timer = nil
    }

    public func scanNow() {
        let agents = self.monitoredAgents
        scanQueue.async {
            ProcessMonitor.performScan(agents: agents)
        }
    }

    private nonisolated static func performScan(agents: [MonitoredAgent]) {
        let activeAgents = agents.filter { $0.isEnabled }
        guard !activeAgents.isEmpty else {
            AgentActivityDetector.shared.reset()
            Task { @MainActor in
                ProcessMonitor.shared.runningAgentNames = []
                ProcessMonitor.shared.runningAgentCount = 0
                ProcessMonitor.shared.hasRunningAgent = false
                ProcessMonitor.shared.activeProcesses = [:]
            }
            return
        }

        // Get all running PIDs
        let maxPids = 4096
        var pids = [pid_t](repeating: 0, count: maxPids)
        let numBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * maxPids))
        guard numBytes > 0 else { return }

        let count = Int(numBytes) / MemoryLayout<pid_t>.size
        var detectedNames = Set<String>()
        var detectedPIDsMap: [String: [pid_t]] = [:]
        var activityPIDsMap: [UUID: Set<pid_t>] = [:]
        var parentByPID: [pid_t: pid_t] = [:]

        var nameBuffer = [CChar](repeating: 0, count: 256)
        var pathBuffer = [CChar](repeating: 0, count: 4096)

        for i in 0..<count {
            let pid = pids[i]
            if pid <= 0 { continue }

            // Get process name
            let nameLen = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let procName = nameLen > 0 ? String(cString: nameBuffer).lowercased() : ""

            // Get process path
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let procPath = pathLen > 0 ? String(cString: pathBuffer).lowercased() : ""
            let lastPathComponent = (procPath as NSString).lastPathComponent.lowercased()

            var bsdInfo = proc_bsdinfo()
            let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdInfoSize) == bsdInfoSize {
                parentByPID[pid] = pid_t(bsdInfo.pbi_ppid)
            }

            for agent in activeAgents {
                var matched = false
                let normalizedProcessNames = agent.processNames.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                let requiresActivity = normalizedProcessNames.contains {
                    activityAwareProcessNames.contains($0)
                }
                for target in normalizedProcessNames {
                    if target.isEmpty { continue }

                    if procName == target || lastPathComponent == target {
                        // Desktop shells are not active CLI generation sessions.
                        if ["claude", "opencode", "opencode2"].contains(target)
                            && procPath.contains(".app/contents/macos/")
                        {
                            continue
                        }
                        matched = true
                        break
                    }

                    // Activity-aware agents are intentionally exact-only: a user's folder
                    // named after an agent must not count as an active backend.
                    if !requiresActivity && (procPath.hasSuffix("/" + target) || procPath.contains("/" + target + "/")) {
                        matched = true
                        break
                    }
                }

                // If not matched by name/path, check process CLI arguments (e.g., node /path/to/claude or python3 -m antigravity)
                if !matched && (procName == "node" || procName == "python" || procName == "python3" || procName == "bun" || procName == "deno" || procName == "sh" || procName == "zsh" || procName == "bash" || procName == "ruby") {
                    if let cmdLine = getProcessCommandLine(pid: pid) {
                        for targetName in agent.processNames {
                            let target = targetName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            if !target.isEmpty && cmdLine.contains(target) {
                                matched = true
                                break
                            }
                        }
                    }
                }

                if matched {
                    if requiresActivity {
                        activityPIDsMap[agent.id, default: []].insert(pid)
                    } else {
                        detectedNames.insert(agent.name)
                        detectedPIDsMap[agent.name, default: []].append(pid)
                    }
                }
            }
        }

        for agent in activeAgents {
            guard let rootPIDs = activityPIDsMap[agent.id], !rootPIDs.isEmpty else {
                _ = AgentActivityDetector.shared.isActive(
                    agentID: agent.id,
                    rootPIDs: [],
                    parentByPID: parentByPID
                )
                continue
            }
            if AgentActivityDetector.shared.isActive(
                agentID: agent.id,
                rootPIDs: rootPIDs,
                parentByPID: parentByPID
            ) {
                detectedNames.insert(agent.name)
                detectedPIDsMap[agent.name] = Array(rootPIDs).sorted()
            }
        }

        let finalNames = detectedNames
        let finalCount = detectedNames.count
        let finalHasRunning = !detectedNames.isEmpty
        let finalPIDsMap = detectedPIDsMap

        Task { @MainActor in
            ProcessMonitor.shared.runningAgentNames = finalNames
            ProcessMonitor.shared.runningAgentCount = finalCount
            ProcessMonitor.shared.hasRunningAgent = finalHasRunning
            ProcessMonitor.shared.activeProcesses = finalPIDsMap
        }
    }

    private nonisolated static func getProcessCommandLine(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size <= 0 {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return nil
        }
        guard size > MemoryLayout<Int32>.size else { return nil }
        return buffer.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return nil }
            let rawPtr = UnsafeRawPointer(baseAddress).advanced(by: MemoryLayout<Int32>.size)
            let rawBytes = [UInt8](UnsafeBufferPointer(start: rawPtr.assumingMemoryBound(to: UInt8.self), count: size - MemoryLayout<Int32>.size))
            let cleanedBytes = rawBytes.map { $0 == 0 ? UInt8(ascii: " ") : $0 }
            return String(bytes: cleanedBytes, encoding: .utf8)?.lowercased()
        }
    }
}
