//
//  ClosedDisplayModeManager.swift
//  Awake
//

import AppKit
import Combine
import Foundation

/// Owns a helper process that disables clamshell sleep while Awake is active.
/// While the lid is closed, the helper also turns on the system-wide
/// SleepDisabled setting, because powerd can clear the clamshell override at
/// any time on battery. The helper holds both only while its stdin remains
/// open, so it restores normal lid behavior even if Awake exits without
/// notification.
@MainActor
public final class ClosedDisplayModeManager: NSObject, ObservableObject {
    public static let shared = ClosedDisplayModeManager()

    @Published public private(set) var lastError: String?
    @Published public private(set) var isHelperInstalled = false
    @Published public private(set) var isCheckingHelper = false
    @Published public private(set) var hasCheckedHelper = false

    public var needsHelperPermissionHint: Bool {
        hasCheckedHelper && !isHelperInstalled
    }

    private let helperURL: URL
    private let helperCheck: () async -> Bool
    private let sleepMarkerPath: String

    private var process: Process?
    private var input: Pipe?
    private var requested = false
    private var isStopping = false
    private var restorationFailed = false
    private var recoveryTask: Task<Bool, Never>?
    /// Bounds automatic helper checks from the heartbeat while the helper is
    /// missing, outdated, or keeps exiting. Each check launches the helper.
    private var lastAutomaticCheck: Date?
    private let automaticCheckInterval: TimeInterval = 15

    init(
        helperURL: URL = SMCHelper.shared.closedDisplayHelperURL,
        helperCheck: @escaping () async -> Bool = { await SMCHelper.shared.refreshHelperInstallState() },
        sleepMarkerPath: String = "/var/db/pmgwork.awake.sleepdisabled"
    ) {
        self.helperURL = helperURL
        self.helperCheck = helperCheck
        self.sleepMarkerPath = sleepMarkerPath
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(stop), name: NSApplication.willTerminateNotification, object: nil
        )
    }

    public func update(sessionActive: Bool, enabled: Bool) {
        requested = sessionActive && enabled
        guard requested else {
            stop()
            return
        }
        if let process {
            // Wait for a previous helper to release the override before
            // starting another one, including after a rapid stop/start.
            if process.isRunning { return }
            self.process = nil
            input = nil
        }
        guard !isCheckingHelper else { return }
        let now = Date()
        if let lastAutomaticCheck, now.timeIntervalSince(lastAutomaticCheck) < automaticCheckInterval {
            return
        }
        lastAutomaticCheck = now
        Task { await refreshHelperState() }
    }

    public func refreshHelperState() async {
        // An install/removal refresh must not return an older in-flight result.
        while isCheckingHelper {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        isCheckingHelper = true
        isHelperInstalled = await helperCheck()
        hasCheckedHelper = true
        isCheckingHelper = false
        guard requested else { return }
        guard isHelperInstalled else {
            lastError = L10n.string("Install or update the helper in Permissions to stay awake with the lid closed.")
            return
        }
        // Let any in-flight startup recovery finish before launching a new
        // clamshell holder so recover-sleep cannot clear the new lease's flag.
        if let recoveryTask {
            _ = await recoveryTask.value
        }
        guard requested, isHelperInstalled, process == nil else { return }
        start()
    }

    private func start() {
        isStopping = false
        restorationFailed = false
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = helperURL
        process.arguments = ["hold-clamshell"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            handle.readabilityHandler = nil
            guard let self, let process else { return }
            Task { @MainActor in self.handleReady(data, from: process) }
        }
        process.terminationHandler = { [weak self] process in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self, self.process === process else { return }
                self.process = nil
                self.input = nil
                if self.isStopping && process.terminationStatus != 0 {
                    self.restorationFailed = true
                }
                if self.requested && self.isStopping && process.terminationStatus == 0 {
                    await self.refreshHelperState()
                } else if self.requested {
                    self.lastError = L10n.string("Couldn't keep the Mac awake with the lid closed.")
                } else if process.terminationStatus != 0 {
                    self.lastError = L10n.string("Couldn't restore normal sleep when the lid closes.")
                }
            }
        }
        do {
            try process.run()
            self.process = process
            self.input = input
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            lastError = error.localizedDescription
            NSLog("[ClosedDisplayModeManager] Failed to start helper: %@", error.localizedDescription)
        }
    }

    /// While the lid is closed, the helper also turns on the system-wide
    /// SleepDisabled setting, which pmset saves. If a helper was killed before
    /// it could restore that setting (for example by a crash or restart), the
    /// helper restores it here.
    @discardableResult
    public func recoverSleepSettingIfNeeded() async -> Bool {
        if let recoveryTask {
            return await recoveryTask.value
        }
        guard process == nil else { return true }
        let task = Task { await performSleepRecovery() }
        recoveryTask = task
        let recovered = await task.value
        recoveryTask = nil
        return recovered
    }

    private func performSleepRecovery() async -> Bool {
        guard process == nil else { return true }
        guard await helperCheck() else { return false }
        guard process == nil else { return true }
        let recovery = Process()
        recovery.executableURL = helperURL
        recovery.arguments = ["recover-sleep"]
        recovery.standardInput = FileHandle.nullDevice
        recovery.standardOutput = FileHandle.nullDevice
        recovery.standardError = FileHandle.nullDevice
        let status: Int32? = await withCheckedContinuation { continuation in
            recovery.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try recovery.run()
            } catch {
                recovery.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
        if status == 0 {
            restorationFailed = false
            return true
        }
        NSLog("[ClosedDisplayModeManager] Could not recover the sleep setting (status: %d)", status ?? -1)
        return false
    }

    public func prepareForHelperRemoval() async -> Bool {
        let retiringProcess = process
        stop()
        if let retiringProcess {
            let deadline = Date().addingTimeInterval(3)
            while retiringProcess.isRunning, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
            return !retiringProcess.isRunning && retiringProcess.terminationStatus == 0
        }
        let hasMarker = FileManager.default.fileExists(atPath: sleepMarkerPath)
        guard restorationFailed || hasMarker else { return true }
        return await recoverSleepSettingIfNeeded()
    }

    private func handleReady(_ data: Data, from process: Process) {
        guard self.process === process, requested, !isStopping else { return }
        if data == Data("ready\n".utf8), process.isRunning {
            lastError = nil
        } else {
            lastError = L10n.string("Couldn't keep the Mac awake with the lid closed.")
        }
    }

    @objc private func stop() {
        requested = false
        // A new session checks the helper right away.
        lastAutomaticCheck = nil
        // Called on every heartbeat while idle; @Published fires on every assignment.
        if lastError != nil { lastError = nil }
        guard process != nil else { return }
        isStopping = true
        // A normal stop still goes through the helper's restoration path.
        input?.fileHandleForWriting.closeFile()
        input = nil
        // Keep the process until the termination callback records restoration
        // success/failure, even if it has already exited.
    }
}
