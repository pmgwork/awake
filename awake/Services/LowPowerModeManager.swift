//
//  LowPowerModeManager.swift
//  Awake
//

import AppKit
import Combine
import Foundation

/// Owns a helper process that turns on Low Power Mode while the lid is closed
/// during a session. The helper restores the previous setting when its stdin
/// closes, on a signal, or when Awake exits. The previous setting is also
/// saved here, so it can be restored on the next launch if the helper could
/// not restore it.
@MainActor
public final class LowPowerModeManager: NSObject, ObservableObject {
    public static let shared = LowPowerModeManager()

    @Published public private(set) var lastError: String?

    private let helperURL: URL
    private let helperCheck: () async -> Bool
    private let readState: () async -> LowPowerModeState?
    private let defaults: UserDefaults

    private var process: Process?
    private var input: Pipe?
    private var requested = false
    /// Set once a request has been handled (held, already in Low Power Mode,
    /// or failed) so the 1 Hz heartbeat does not retry until the next request.
    private var handledRequest = false
    private var isStopping = false
    private var restoreTask: Task<Void, Never>?

    private static let savedStateKey = "pmgwork.awake.lowPowerModeSavedState"

    init(
        helperURL: URL = SMCHelper.shared.closedDisplayHelperURL,
        helperCheck: @escaping () async -> Bool = { await SMCHelper.shared.refreshHelperInstallState() },
        readState: @escaping () async -> LowPowerModeState? = { await LowPowerModeState.readCurrent() },
        defaults: UserDefaults = .standard
    ) {
        self.helperURL = helperURL
        self.helperCheck = helperCheck
        self.readState = readState
        self.defaults = defaults
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(stop), name: NSApplication.willTerminateNotification, object: nil
        )
    }

    public func update(requested: Bool) {
        guard requested else {
            stop()
            return
        }
        guard !self.requested else { return }
        self.requested = true
        handledRequest = false
        Task { await start() }
    }

    private func start() async {
        // Wait for a previous helper to restore the setting first, including
        // after a rapid stop/start; its termination retries the request.
        guard process == nil else { return }
        await restoreSavedStateIfNeeded()
        guard requested, !handledRequest, process == nil else { return }
        handledRequest = true
        guard await helperCheck() else {
            if requested {
                lastError = L10n.string("Install or update the helper in Permissions to use Low Power Mode with the lid closed.")
            }
            return
        }
        guard requested else { return }
        guard let state = await readState() else {
            if requested { lastError = L10n.string("Low Power Mode isn't available on this Mac.") }
            return
        }
        guard requested, process == nil else { return }
        lastError = nil
        guard !state.isLowPowerEverywhere else { return }
        saveState(state)
        launch(arguments: ["hold-lowpower"] + state.helperArguments)
    }

    private func launch(arguments: [String]) {
        isStopping = false
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = helperURL
        process.arguments = arguments
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
                if process.terminationStatus == 0 {
                    self.clearSavedState()
                } else {
                    self.lastError = self.requested && !self.isStopping
                        ? L10n.string("Couldn't turn on Low Power Mode.")
                        : L10n.string("Couldn't restore the previous Low Power Mode setting.")
                    await self.restoreSavedStateIfNeeded()
                }
                // A request made while the previous helper was restoring.
                if self.requested && self.isStopping {
                    self.handledRequest = false
                    await self.start()
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
            clearSavedState()
            NSLog("[LowPowerModeManager] Failed to start helper: %@", error.localizedDescription)
        }
    }

    private func handleReady(_ data: Data, from process: Process) {
        guard self.process === process, requested, !isStopping else { return }
        if data == Data("ready\n".utf8), process.isRunning {
            lastError = nil
        } else {
            lastError = L10n.string("Couldn't turn on Low Power Mode.")
        }
    }

    @objc private func stop() {
        requested = false
        handledRequest = false
        guard process != nil else {
            // Called on every heartbeat while idle; @Published fires on every assignment.
            if lastError != nil { lastError = nil }
            return
        }
        isStopping = true
        // A normal stop still goes through the helper's restoration path.
        input?.fileHandleForWriting.closeFile()
        input = nil
        // Keep the process until the termination callback records restoration
        // success/failure, even if it has already exited.
    }

    public func prepareForHelperRemoval() async -> Bool {
        let retiringProcess = process
        stop()
        if let retiringProcess {
            let deadline = Date().addingTimeInterval(5)
            while process === retiringProcess, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
            // The termination callback has not recorded the result yet.
            guard process !== retiringProcess else { return false }
        }
        // The helper must stay until a saved setting has been restored.
        await restoreSavedStateIfNeeded()
        return savedState() == nil
    }

    // MARK: - Saved State

    /// Restores a setting saved by a session whose helper did not restore it
    /// (for example after a restart or a crash), unless the user has changed
    /// it since. Concurrent callers wait for the same attempt.
    public func restoreSavedStateIfNeeded() async {
        if let restoreTask {
            await restoreTask.value
            return
        }
        guard process == nil, savedState() != nil else { return }
        let task = Task { await performRestore() }
        restoreTask = task
        await task.value
        restoreTask = nil
    }

    private func performRestore() async {
        guard let saved = savedState(), let current = await readState() else { return }
        guard let restoration = saved.restoration(from: current) else {
            clearSavedState()
            return
        }
        guard await helperCheck() else { return }
        if await runHelper(arguments: ["set-lowpower"] + restoration.helperArguments) {
            clearSavedState()
        } else {
            NSLog("[LowPowerModeManager] Could not restore Low Power Mode; will retry")
        }
    }

    private func runHelper(arguments: [String]) async -> Bool {
        let process = Process()
        process.executableURL = helperURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
    }

    private func savedState() -> LowPowerModeState? {
        defaults.data(forKey: Self.savedStateKey)
            .flatMap { try? JSONDecoder().decode(LowPowerModeState.self, from: $0) }
    }

    private func saveState(_ state: LowPowerModeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.savedStateKey)
    }

    private func clearSavedState() {
        defaults.removeObject(forKey: Self.savedStateKey)
    }
}
