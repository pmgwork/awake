//
//  SMCHelper.swift
//  Awake
//

import Foundation
import AppKit
import CryptoKit
import Darwin

public nonisolated final class SMCHelper: @unchecked Sendable {
    public static let shared = SMCHelper()

    private let helperToolPath = "/Library/PrivilegedHelperTools/pmgwork.awake.smc"
    static let helperProtocolVersion = "awake-smc-15"
    static let bundledHelperURL = Bundle.main.bundleURL
        .appendingPathComponent("Contents/Helpers/pmgwork.awake.smc", isDirectory: false)

    var closedDisplayHelperURL: URL { URL(fileURLWithPath: helperToolPath) }
    private let fanLeaseLock = NSLock()
    private var fanLeaseProcess: Process?
    private let terminationLock = NSLock()
    private var terminationRequested = false
    private let readinessTimeout: TimeInterval = 45

    private let installStateLock = NSLock()
    private let installCheckLock = NSLock()
    private let helperMutationLock = NSLock()
    private let installCheckQueue = DispatchQueue(label: "pmgwork.awake.smchelper.installcheck", qos: .utility)
    private var cachedInstallCheck: (date: Date, installed: Bool)?
    private let installCheckTTL: TimeInterval = 30

    private init() {}

    public func isHelperToolPresent() -> Bool {
        FileManager.default.fileExists(atPath: helperToolPath)
    }

    /// Whether a helper check has finished since launch, so callers can tell
    /// a missing helper from one that has not been checked yet.
    public var hasCheckedHelperInstallState: Bool { cachedInstallState != nil }

    /// Returns whether the installed helper matches the expected protocol version.
    ///
    /// The check launches the helper binary and waits for it, so it must never
    /// run on the main thread: synchronous process waits pump the calling
    /// thread's run loop and can re-enter AppKit/SwiftUI from inside a view
    /// update. Main-thread callers receive the cached value while a background
    /// refresh is scheduled.
    public func checkHelperInstalled() -> Bool {
        if Thread.isMainThread {
            let cached = cachedInstallState
            refreshHelperInstallStateInBackground()
            return cached ?? false
        }
        return performInstallCheck(usingCache: true)
    }

    /// Re-runs the helper check on a background queue and updates the cache.
    public func refreshHelperInstallState() async -> Bool {
        await withCheckedContinuation { continuation in
            installCheckQueue.async {
                continuation.resume(returning: self.performInstallCheck(usingCache: false))
            }
        }
    }

    /// Warms the cached helper state at launch so the first fan or battery
    /// assertion does not race the asynchronous check.
    public func prewarmHelperInstallState() {
        refreshHelperInstallStateInBackground()
    }

    // MARK: - Helper Installation State

    private var cachedInstallState: Bool? {
        installStateLock.lock()
        defer { installStateLock.unlock() }
        return cachedInstallCheck?.installed
    }

    private var freshCachedInstallState: Bool? {
        installStateLock.lock()
        defer { installStateLock.unlock() }
        guard let cachedInstallCheck,
              Date().timeIntervalSince(cachedInstallCheck.date) < installCheckTTL else {
            return nil
        }
        return cachedInstallCheck.installed
    }

    private func storeInstallState(_ installed: Bool) {
        installStateLock.lock()
        cachedInstallCheck = (Date(), installed)
        installStateLock.unlock()
    }

    private func refreshHelperInstallStateInBackground() {
        installCheckQueue.async { [weak self] in
            _ = self?.performInstallCheck(usingCache: true)
        }
    }

    private func performInstallCheck(usingCache: Bool) -> Bool {
        if usingCache, let cached = freshCachedInstallState {
            return cached
        }

        // Serialize cache misses so concurrent callers cannot launch the helper
        // multiple times.
        installCheckLock.lock()
        defer { installCheckLock.unlock() }

        if usingCache, let cached = freshCachedInstallState {
            return cached
        }

        // A version check that times out under load says nothing about the
        // helper. Keep the last known state instead of hiding fan control and
        // dropping a running cooling mode.
        let installed = readInstalledHelperVersion() ?? cachedInstallState ?? false
        storeInstallState(installed)
        return installed
    }

    /// Returns `nil` when the helper did not answer in time.
    private func readInstalledHelperVersion() -> Bool? {
        guard FileManager.default.isExecutableFile(atPath: helperToolPath),
              let attributes = try? FileManager.default.attributesOfItem(atPath: helperToolPath),
              (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              (attributes[.groupOwnerAccountID] as? NSNumber)?.intValue == 80,
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o4000 != 0,
              permissions & 0o0022 == 0 else {
            return false
        }

        let proc = Process()
        let stdout = Pipe()
        proc.executableURL = URL(fileURLWithPath: helperToolPath)
        proc.arguments = ["version"]
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            guard waitForExit(proc, timeout: 2) else { return nil }
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return proc.terminationStatus == 0 && output == Self.helperProtocolVersion
        } catch {
            return false
        }
    }

    /// Waits for a launched process without pumping the caller's run loop and
    /// terminates it when it exceeds the timeout.
    private func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard process.isRunning else { return true }

        NSLog(
            "[SMCHelper] Process %d did not exit within %.1fs; terminating.",
            process.processIdentifier,
            timeout
        )
        process.terminate()
        let killDeadline = Date().addingTimeInterval(1)
        while process.isRunning, Date() < killDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    /// Sets maximum mode through the installed helper, with direct/authorization fallbacks.
    public func setFanMaximum() -> Bool {
        if checkHelperInstalled() {
            return startInstalledFanControlLease(mode: "max")
        }

        if SMCClient.shared.setAllFansMax() {
            NSLog("[SMCHelper] Direct SMC set max succeeded")
            return true
        }

        NSLog("[SMCHelper] Direct SMC write requires root privileges, attempting elevated execution...")
        return runPrivilegedFanCommand(mode: "max")
    }

    public func setFanAggressive() -> Bool {
        if checkHelperInstalled() {
            return startInstalledFanControlLease(mode: "aggressive")
        }

        if SMCClient.shared.setAllFansAggressive() {
            NSLog("[SMCHelper] Direct SMC set aggressive succeeded")
            return true
        }

        NSLog("[SMCHelper] Direct SMC write requires root privileges, attempting privileged helper...")
        return runPrivilegedFanCommand(mode: "aggressive")
    }

    public func setFanModerate() -> Bool {
        if checkHelperInstalled() {
            return startInstalledFanControlLease(mode: "moderate")
        }

        if SMCClient.shared.setAllFansModerate() {
            NSLog("[SMCHelper] Direct SMC set moderate succeeded")
            return true
        }

        NSLog("[SMCHelper] Direct SMC write requires root privileges, attempting privileged helper...")
        return runPrivilegedFanCommand(mode: "moderate")
    }

    /// Restores automatic mode through the installed helper, with direct/authorization fallbacks.
    public func setFanAuto(allowAuthorizationPrompt: Bool = true) -> Bool {
        stopInstalledFanControlLease()
        if let helperResult = runInstalledHelperCommand(mode: "auto") {
            return helperResult
        }

        if SMCClient.shared.setAllFansAuto() {
            NSLog("[SMCHelper] Direct SMC set auto succeeded")
            return true
        }

        NSLog("[SMCHelper] Direct SMC write requires root privileges, attempting elevated execution...")
        return runPrivilegedFanCommand(mode: "auto", allowAuthorizationPrompt: allowAuthorizationPrompt)
    }

    /// Runs privileged fan control command via AppleScript / authorization
    public func runPrivilegedFanCommand(mode: String, allowAuthorizationPrompt: Bool = true) -> Bool {
        if let helperResult = runInstalledHelperCommand(mode: mode) {
            return helperResult
        }

        guard allowAuthorizationPrompt else { return false }

        // Manual modes must run under a lease that restores system control when
        // Awake exits or crashes. A one-shot privileged command would leave the
        // fans pinned with no owning process, so install the helper (same single
        // authorization prompt) and start the normal lease instead.
        if mode != "auto" {
            guard installHelperToolSynchronously() else {
                NSLog("[SMCHelper] Helper installation was cancelled or failed; refusing unsupervised fan control")
                return false
            }
            return startInstalledFanControlLease(mode: mode)
        }

        guard let digest = bundledHelperDigest() else { return false }
        let command = stagedHelperCommand(
            directory: "/private/tmp",
            expectedSHA256: digest,
            action: "\"$binary\" \(shellQuote(mode))"
        )
        return runAuthorizedHelperCommand(command)
    }

    private func runInstalledHelperCommand(mode: String) -> Bool? {
        guard checkHelperInstalled() else { return nil }

        let proc = Process()
        let stderr = Pipe()
        proc.executableURL = URL(fileURLWithPath: helperToolPath)
        proc.arguments = [mode]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = stderr
        do {
            try proc.run()
            guard waitForExit(proc, timeout: 5) else {
                NSLog("[SMCHelper] Privileged helper command timed out (mode: %@)", mode)
                return false
            }
            let success = proc.terminationStatus == 0
            if success {
                NSLog("[SMCHelper] Privileged helper command succeeded (mode: %@)", mode)
            } else {
                let detail = String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                NSLog(
                    "[SMCHelper] Privileged helper command failed (mode: %@, exit status: %d, detail: %@)",
                    mode,
                    proc.terminationStatus,
                    detail?.isEmpty == false ? detail! : "none"
                )
            }
            return success
        } catch {
            NSLog("[SMCHelper] Failed to launch privileged helper: %@", error.localizedDescription)
            return false
        }
    }

    /// Starts a helper that owns the manual fan override and watches the Awake
    /// process. If Awake exits or crashes, the helper restores system control.
    private func startInstalledFanControlLease(mode: String) -> Bool {
        guard stopInstalledFanControlLease() else {
            NSLog("[SMCHelper] Previous fan control lease did not exit; skipping mode %@", mode)
            return false
        }

        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: helperToolPath)
        process.arguments = [mode, "watch-parent"]
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            NSLog("[SMCHelper] Fan control lease exited (status: %d)", process.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            NSLog("[SMCHelper] Failed to start fan control lease: %@", error.localizedDescription)
            return false
        }

        // Publish the process before waiting for readiness so a concurrent
        // stop (mode change or app termination) can cancel it immediately
        // instead of blocking on the lock for the whole engage.
        fanLeaseLock.lock()
        fanLeaseProcess = process
        fanLeaseLock.unlock()

        guard waitForReadiness(process, stdout: stdout, timeout: readinessTimeout),
              process.isRunning else {
            fanLeaseLock.lock()
            if fanLeaseProcess === process {
                fanLeaseProcess = nil
            }
            fanLeaseLock.unlock()
            if process.isRunning {
                process.terminate()
            }
            NSLog("[SMCHelper] Fan control lease did not become ready")
            return false
        }

        NSLog("[SMCHelper] Fan control lease started (mode: %@, PID: %d)", mode, process.processIdentifier)
        return true
    }

    /// Whether the helper that holds the manual fan override is still running.
    public var isFanControlLeaseRunning: Bool {
        fanLeaseLock.lock()
        defer { fanLeaseLock.unlock() }
        return fanLeaseProcess?.isRunning == true
    }

    /// Waits for the helper's READY handshake. The wait is bounded and checks
    /// the termination flag so quitting Awake cannot hang behind a slow SMC
    /// engage.
    private func waitForReadiness(_ process: Process, stdout: Pipe, timeout: TimeInterval) -> Bool {
        let handle = stdout.fileHandleForReading
        let deadline = Date().addingTimeInterval(timeout)
        var output = Data()

        while Date() < deadline {
            if isTerminationRequested || !process.isRunning {
                return false
            }
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&descriptor, 1, 250)
            if pollResult < 0 {
                if errno == EINTR { continue }
                return false
            }
            if pollResult == 0 { continue }

            guard let chunk = try? handle.read(upToCount: 6), !chunk.isEmpty else {
                return false
            }
            output.append(chunk)
            if output.count >= 6 {
                break
            }
        }

        guard output.count >= 6 else { return false }
        return String(data: output.prefix(6), encoding: .utf8)?.hasPrefix("READY") == true
    }

    /// Asks any in-flight helper startup to stop waiting so app termination is
    /// not blocked by a slow SMC engage.
    public func requestTermination() {
        terminationLock.lock()
        terminationRequested = true
        terminationLock.unlock()
    }

    private var isTerminationRequested: Bool {
        terminationLock.lock()
        defer { terminationLock.unlock() }
        return terminationRequested
    }

    @discardableResult
    private func stopInstalledFanControlLease() -> Bool {
        fanLeaseLock.lock()
        defer { fanLeaseLock.unlock() }
        return stopInstalledFanControlLeaseLocked()
    }

    /// Stops the lease and waits until the helper has actually exited. The old
    /// helper's rollback must never overlap a replacement lease's engagement.
    @discardableResult
    private func stopInstalledFanControlLeaseLocked() -> Bool {
        guard let process = fanLeaseProcess else { return true }
        fanLeaseProcess = nil
        guard process.isRunning else { return true }

        process.terminate()
        if waitForExitWithoutTerminating(process, timeout: 6) {
            return true
        }

        // A helper that ignores SIGTERM would keep writing manual fan targets
        // while a replacement lease runs. Make sure it is really gone.
        NSLog("[SMCHelper] Fan control lease did not exit after SIGTERM; sending SIGKILL")
        kill(process.processIdentifier, SIGKILL)
        if waitForExitWithoutTerminating(process, timeout: 2) {
            return true
        }
        NSLog("[SMCHelper] Fan control lease is still running (PID: %d)", process.processIdentifier)
        return false
    }

    private func waitForExitWithoutTerminating(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        return !process.isRunning
    }

    /// Installs the privileged helper tool once so future fan changes don't require admin password prompts
    public func installHelperTool(completion: @escaping (Bool) -> Void) {
        // NSAppleScript's authorization work is performed by macOS at Default QoS.
        // Running this block at a higher QoS while synchronously awaiting that work
        // triggers Thread Performance Checker priority-inversion warnings.
        DispatchQueue.global(qos: .default).async {
            let success = self.installHelperToolSynchronously()
            DispatchQueue.main.async { completion(success) }
        }
    }

    /// Call only after the coordinator has released all hardware leases.
    public func removeHelperTool() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .default).async {
                self.helperMutationLock.lock()
                defer { self.helperMutationLock.unlock() }
                let command = "/bin/rm -f -- \(self.shellQuote(self.helperToolPath))"
                guard let script = NSAppleScript(source: self.authorizedAppleScriptSource(command: command)) else {
                    continuation.resume(returning: false)
                    return
                }
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                let removed = error == nil && !self.isHelperToolPresent()
                if removed { self.storeInstallState(false) }
                continuation.resume(returning: removed)
            }
        }
    }

    /// Synchronous helper install used by `installHelperTool` and by the manual
    /// fan fallback, which must never leave fans in manual mode without a
    /// parent-watching lease.
    private func installHelperToolSynchronously() -> Bool {
        helperMutationLock.lock()
        defer { helperMutationLock.unlock() }
        guard let digest = bundledHelperDigest() else { return false }
        let destination = shellQuote(helperToolPath)
        let directory = URL(fileURLWithPath: helperToolPath).deletingLastPathComponent().path
        let command = stagedHelperCommand(
            directory: directory,
            expectedSHA256: digest,
            action: "/usr/sbin/chown root:admin \"$binary\"; /bin/chmod 4750 \"$binary\"; /bin/mv -f \"$binary\" \(destination)"
        )
        guard runAuthorizedHelperCommand(command) else { return false }

        return performInstallCheck(usingCache: false)
    }

    private func bundledHelperDigest() -> String? {
        let url = Self.bundledHelperURL
        guard FileManager.default.isExecutableFile(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            NSLog("[SMCHelper] Could not read bundled helper at %@", url.path)
            return nil
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func runAuthorizedHelperCommand(_ command: String) -> Bool {
        guard let script = NSAppleScript(source: authorizedAppleScriptSource(command: command)) else {
            return false
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            NSLog("[SMCHelper] AppleScript authorization error: %@", error)
            return false
        }
        return true
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func authorizedAppleScriptSource(command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    private func stagedHelperCommand(
        directory: String,
        expectedSHA256: String,
        action: String
    ) -> String {
        let source = shellQuote(Self.bundledHelperURL.path)
        let template = shellQuote(directory + "/.awake-smc.XXXXXXXX")
        let digest = shellQuote(expectedSHA256)
        // Stage on the destination volume for an atomic install. The Mach-O
        // signature stays intact when copying without the bundle's extended attributes.
        return [
            "set -e",
            "umask 077",
            "/bin/mkdir -p \(shellQuote(directory))",
            "stage=$(/usr/bin/mktemp -d \(template))",
            "trap '/bin/rm -rf \"$stage\"' EXIT",
            "binary=\"$stage/pmgwork.awake.smc\"",
            "/bin/cp -X \(source) \"$binary\"",
            "/bin/chmod 0700 \"$binary\"",
            "actual=$(/usr/bin/shasum -a 256 \"$binary\" | /usr/bin/awk '{print $1}')",
            "test \"$actual\" = \(digest)",
            action,
        ].joined(separator: "; ")
    }
}
