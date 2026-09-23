//
//  ClosedDisplayModeManager.swift
//  Awake
//

import AppKit
import Combine
import Foundation

/// Owns a helper process that disables clamshell sleep while Awake is active.
/// The helper holds the override only while its stdin remains open, so it
/// restores normal lid behavior even if Awake exits without notification.
@MainActor
public final class ClosedDisplayModeManager: NSObject, ObservableObject {
    public static let shared = ClosedDisplayModeManager()

    @Published public private(set) var isActive = false
    @Published public private(set) var lastError: String?

    private var process: Process?
    private var input: Pipe?
    private var requested = false

    private override init() {
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
            isActive = false
            self.process = nil
            input = nil
        }
        start()
    }

    private func start() {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/AwakeHookBridge")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            lastError = "The closed-display helper is missing."
            return
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = helperURL
        process.arguments = ["--clamshell-lease"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            handle.readabilityHandler = nil
            guard let self, let process else { return }
            Task { @MainActor in self.handleReady(data, from: process) }
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

    private func handleReady(_ data: Data, from process: Process) {
        guard self.process === process, requested else { return }
        if data == Data("ready\n".utf8), process.isRunning {
            isActive = true
            lastError = nil
        } else {
            lastError = "The closed-display override could not be enabled."
        }
    }

    @objc private func stop() {
        requested = false
        lastError = nil
        guard let process else { return }
        isActive = false
        // A normal stop still goes through the helper's restoration path.
        input?.fileHandleForWriting.closeFile()
        if !process.isRunning {
            self.process = nil
            input = nil
        }
    }
}
