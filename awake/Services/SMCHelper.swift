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
    private let helperProtocolVersion = "awake-smc-10"
    private let fanLeaseLock = NSLock()
    private var fanLeaseProcess: Process?
    private let terminationLock = NSLock()
    private var terminationRequested = false
    private let readinessTimeout: TimeInterval = 45

    private let installStateLock = NSLock()
    private let installCheckLock = NSLock()
    private let installCheckQueue = DispatchQueue(label: "pmgwork.awake.smchelper.installcheck", qos: .utility)
    private var cachedInstallCheck: (date: Date, installed: Bool)?
    private let installCheckTTL: TimeInterval = 30

    private init() {}

    public func isHelperToolPresent() -> Bool {
        FileManager.default.fileExists(atPath: helperToolPath)
    }

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

        let installed = readInstalledHelperVersion()
        storeInstallState(installed)
        return installed
    }

    private func readInstalledHelperVersion() -> Bool {
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
            guard waitForExit(proc, timeout: 2) else { return false }
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return proc.terminationStatus == 0 && output == helperProtocolVersion
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

        let helperSource = generateHelperSource()
        guard let tempDirectory = createPrivateTemporaryDirectory() else { return false }
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let tempSourcePath = tempDirectory.appendingPathComponent("awake_smc_once.c").path
        let tempBinaryPath = tempDirectory.appendingPathComponent("awake_smc_once").path

        do {
            try helperSource.write(toFile: tempSourcePath, atomically: true, encoding: .utf8)

            let compileProc = Process()
            compileProc.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
            compileProc.arguments = [
                tempSourcePath, "-o", tempBinaryPath, "-O2",
                "-framework", "IOKit", "-framework", "CoreFoundation"
            ]
            try compileProc.run()
            compileProc.waitUntilExit()
            guard compileProc.terminationStatus == 0 else {
                NSLog("[SMCHelper] Failed to compile one-shot helper")
                return false
            }

            guard let digest = sha256(atPath: tempBinaryPath) else { return false }
            let stagedPath = "/private/tmp/awake-smc-\(UUID().uuidString)"
            let command = secureRootExecutionCommand(
                sourcePath: tempBinaryPath,
                stagedPath: stagedPath,
                expectedSHA256: digest,
                arguments: [mode]
            )
            let appleScriptSource = authorizedAppleScriptSource(command: command)

            if let appleScript = NSAppleScript(source: appleScriptSource) {
                var errorDict: NSDictionary?
                appleScript.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    NSLog("[SMCHelper] AppleScript authorization error: %@", error)
                    return false
                }
                return true
            }
        } catch {
            NSLog("[SMCHelper] Failed to write temporary fan script: %@", error.localizedDescription)
        }

        return false
    }

    /// Returns nil when no valid installed helper is available, otherwise the
    /// actual command result. Authorized installations should never attempt a
    /// noisy, guaranteed-to-fail unprivileged SMC write first.
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

    /// Starts a root-owned limited-power assertion. The helper watches its
    /// parent Awake process and releases the assertion on termination or crash.
    public func startBatterySleepAssertion() -> Process? {
        guard checkHelperInstalled() else {
            NSLog("[SMCHelper] Battery sleep assertion requires the current helper version")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperToolPath)
        process.arguments = ["hold-sleep"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            NSLog(
                "[SMCHelper] Battery sleep assertion helper exited (status: %d)",
                process.terminationStatus
            )
        }
        do {
            try process.run()
            NSLog("[SMCHelper] Started battery sleep assertion helper (PID: %d)", process.processIdentifier)
            return process
        } catch {
            NSLog("[SMCHelper] Failed to start battery sleep assertion helper: %@", error.localizedDescription)
            return nil
        }
    }

    /// Installs the privileged helper tool once so future fan changes don't require admin password prompts
    public func installHelperTool(completion: @escaping (Bool) -> Void) {
        // NSAppleScript's authorization work is performed by macOS at Default QoS.
        // Running this block at a higher QoS while synchronously awaiting that work
        // triggers Thread Performance Checker priority-inversion warnings.
        DispatchQueue.global(qos: .default).async {
            let helperSource = self.generateHelperSource()
            guard let tempDirectory = self.createPrivateTemporaryDirectory() else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            defer { try? FileManager.default.removeItem(at: tempDirectory) }
            let tempSourcePath = tempDirectory.appendingPathComponent("smc_helper_source.c").path
            let tempBinaryPath = tempDirectory.appendingPathComponent("pmgwork.awake.smc").path

            do {
                try helperSource.write(toFile: tempSourcePath, atomically: true, encoding: .utf8)

                // Compile locally
                let compileProc = Process()
                compileProc.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
                compileProc.arguments = [
                    tempSourcePath, "-o", tempBinaryPath, "-O2",
                    "-framework", "IOKit", "-framework", "CoreFoundation"
                ]
                try compileProc.run()
                compileProc.waitUntilExit()

                if compileProc.terminationStatus != 0 {
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                guard let digest = self.sha256(atPath: tempBinaryPath) else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                let stagedPath = "/private/tmp/awake-smc-install-\(UUID().uuidString)"
                let installCommand = self.secureRootInstallCommand(
                    sourcePath: tempBinaryPath,
                    stagedPath: stagedPath,
                    expectedSHA256: digest
                )

                // Install with admin privileges
                let appleScriptSource = self.authorizedAppleScriptSource(command: installCommand)
                if let appleScript = NSAppleScript(source: appleScriptSource) {
                    var errorDict: NSDictionary?
                    appleScript.executeAndReturnError(&errorDict)
                    let success = (errorDict == nil)
                    DispatchQueue.main.async {
                        completion(success)
                    }
                    return
                }
            } catch {
                NSLog("[SMCHelper] Installation error: %@", error.localizedDescription)
            }

            DispatchQueue.main.async { completion(false) }
        }
    }

    private func createPrivateTemporaryDirectory() -> URL? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("awake-smc-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            return directory
        } catch {
            NSLog("[SMCHelper] Failed to create private staging directory: %@", error.localizedDescription)
            return nil
        }
    }

    private func sha256(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

    private func secureRootExecutionCommand(
        sourcePath: String,
        stagedPath: String,
        expectedSHA256: String,
        arguments: [String]
    ) -> String {
        let source = shellQuote(sourcePath)
        let staged = shellQuote(stagedPath)
        let digest = shellQuote(expectedSHA256)
        let args = arguments.map(shellQuote).joined(separator: " ")
        return "set -e; umask 077; trap 'rm -f \(stagedPath)' EXIT; cp \(source) \(staged); chown root:wheel \(staged); chmod 0700 \(staged); actual=$(/usr/bin/shasum -a 256 \(staged) | /usr/bin/awk '{print $1}'); test \"$actual\" = \(digest); \(staged) \(args)"
    }

    private func secureRootInstallCommand(
        sourcePath: String,
        stagedPath: String,
        expectedSHA256: String
    ) -> String {
        let source = shellQuote(sourcePath)
        let staged = shellQuote(stagedPath)
        let destination = shellQuote(helperToolPath)
        let digest = shellQuote(expectedSHA256)
        return "set -e; umask 077; trap 'rm -f \(stagedPath)' EXIT; cp \(source) \(staged); chown root:wheel \(staged); chmod 0700 \(staged); actual=$(/usr/bin/shasum -a 256 \(staged) | /usr/bin/awk '{print $1}'); test \"$actual\" = \(digest); mkdir -p /Library/PrivilegedHelperTools; cp \(staged) \(destination); chown root:admin \(destination); chmod 4750 \(destination)"
    }

    private func generateHelperSource() -> String {
        return """
        #include <IOKit/IOKitLib.h>
        #include <CoreFoundation/CoreFoundation.h>
        #include <mach/mach.h>
        #include <stdbool.h>
        #include <stdint.h>
        #include <stdio.h>
        #include <signal.h>
        #include <string.h>
        #include <unistd.h>
        #include <IOKit/pwr_mgt/IOPMLib.h>

        typedef struct {
            uint32_t key;
            uint8_t version[6];
            uint8_t limitData[18];
            uint32_t dataSize;
            uint32_t dataType;
            uint8_t dataAttributes;
            uint8_t keyInfoPadding[3];
            uint8_t result;
            uint8_t status;
            uint8_t command;
            uint8_t commandPadding;
            uint32_t data32;
            uint8_t bytes[32];
        } SMCParam;

        static uint32_t fourCC(const char *s) {
            return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
                   ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
        }

        static kern_return_t callSMC(io_connect_t connection, SMCParam *input, SMCParam *output) {
            size_t outputSize = sizeof(*output);
            return IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &outputSize);
        }

        static bool keyInfo(io_connect_t connection, const char *key, SMCParam *info) {
            SMCParam input = {0};
            input.key = fourCC(key);
            input.command = 9;
            return callSMC(connection, &input, info) == KERN_SUCCESS && info->result == 0;
        }

        static bool readKey(io_connect_t connection, const char *key, uint8_t *bytes, uint32_t *size) {
            SMCParam info = {0};
            if (!keyInfo(connection, key, &info) || info.dataSize > 32) return false;
            SMCParam input = {0}, output = {0};
            input.key = fourCC(key);
            input.dataSize = info.dataSize;
            input.command = 5;
            if (callSMC(connection, &input, &output) != KERN_SUCCESS || output.result != 0) return false;
            memcpy(bytes, output.bytes, info.dataSize);
            *size = info.dataSize;
            return true;
        }

        static bool writeKey(io_connect_t connection, const char *key, const uint8_t *bytes, uint32_t size) {
            SMCParam info = {0};
            if (!keyInfo(connection, key, &info) || info.dataSize != size || size > 32) return false;
            SMCParam input = {0}, output = {0};
            input.key = fourCC(key);
            input.dataSize = info.dataSize;
            input.dataType = info.dataType;
            input.dataAttributes = info.dataAttributes;
            input.command = 6;
            memcpy(input.bytes, bytes, size);
            return callSMC(connection, &input, &output) == KERN_SUCCESS && output.result == 0;
        }

        static volatile sig_atomic_t shouldStop = 0;
        static bool abortOnStop = true;
        static pid_t expectedParentPID = 0;

        static void handleStopSignal(int signalNumber) {
            (void)signalNumber;
            shouldStop = 1;
        }

        static bool parentDied(void) {
            return expectedParentPID > 1 && getppid() != expectedParentPID;
        }

        static bool writeKeyRetry(io_connect_t connection, const char *key, const uint8_t *bytes,
                                  uint32_t size, int attempts, useconds_t delay) {
            for (int attempt = 0; attempt < attempts; ++attempt) {
                if (abortOnStop && (shouldStop || parentDied())) return false;
                if (writeKey(connection, key, bytes, size)) return true;
                if (attempt + 1 < attempts) usleep(delay);
            }
            return false;
        }

        static bool resolveModeKey(io_connect_t connection, int fan, char key[5]) {
            memcpy(key, "F0Md", 5);
            key[1] = (char)('0' + fan);
            SMCParam info = {0};
            if (keyInfo(connection, key, &info)) return true;
            key[2] = 'm';
            key[3] = 'd';
            return keyInfo(connection, key, &info);
        }

        static bool engageManual(io_connect_t connection, const char *modeKey) {
            if (shouldStop || parentDied()) return false;
            uint8_t manual = 1;
            if (writeKey(connection, modeKey, &manual, 1)) return true;

            // M3/M4 thermalmonitord keeps the fans in protected system mode (3).
            // Ftst=1 asks it to yield, which normally takes 3-6 seconds.
            uint8_t unlock = 1;
            if (!writeKeyRetry(connection, "Ftst", &unlock, 1, 100, 50000)) {
                fprintf(stderr, "could not set Ftst=1");
                return false;
            }
            usleep(3000000);
            if (shouldStop || parentDied()) return false;
            if (!writeKeyRetry(connection, modeKey, &manual, 1, 300, 100000)) {
                fprintf(stderr, "thermal manager did not release %s", modeKey);
                return false;
            }
            return true;
        }

        static bool restoreFanAuto(io_connect_t connection, int fan) {
            char modeKey[5] = {0};
            if (!resolveModeKey(connection, fan, modeKey)) return false;

            uint8_t modeBytes[32] = {0};
            uint32_t modeSize = 0;
            bool alreadySystemControlled = readKey(connection, modeKey, modeBytes, &modeSize) &&
                                           modeSize == 1 && modeBytes[0] != 1;
            uint8_t automatic = 0;
            bool modeOK = alreadySystemControlled ||
                          writeKeyRetry(connection, modeKey, &automatic, 1, 20, 50000);

            // Clear a stale target as a best effort. Both flt and fpe2 encode zero
            // as all-zero bytes.
            char targetKey[] = "F0Tg";
            targetKey[1] = (char)('0' + fan);
            SMCParam targetInfo = {0};
            if (keyInfo(connection, targetKey, &targetInfo) && targetInfo.dataSize <= 32) {
                uint8_t zero[32] = {0};
                (void)writeKeyRetry(connection, targetKey, zero, targetInfo.dataSize, 10, 50000);
            }
            return modeOK;
        }

        static void rollbackToAuto(io_connect_t connection, int fanCount) {
            // Rollback must finish even when a stop was requested: turn off the
            // abort checks that guard the manual-engage path.
            abortOnStop = false;
            for (int fan = 0; fan < fanCount; ++fan) {
                (void)restoreFanAuto(connection, fan);
            }
            SMCParam ftstInfo = {0};
            if (keyInfo(connection, "Ftst", &ftstInfo)) {
                uint8_t release = 0;
                (void)writeKeyRetry(connection, "Ftst", &release, 1, 20, 50000);
            }
        }

        static int holdBatterySleepAssertion(void) {
            pid_t awakePID = getppid();
            signal(SIGTERM, handleStopSignal);
            signal(SIGINT, handleStopSignal);

            int level = kIOPMAssertionLevelOn;
            CFNumberRef levelNumber = CFNumberCreate(
                kCFAllocatorDefault,
                kCFNumberIntType,
                &level
            );
            if (!levelNumber) return 9;

            CFMutableDictionaryRef properties = CFDictionaryCreateMutable(
                kCFAllocatorDefault,
                0,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks
            );
            if (!properties) {
                CFRelease(levelNumber);
                return 9;
            }
            CFDictionarySetValue(properties, kIOPMAssertionTypeKey, kIOPMAssertionTypePreventSystemSleep);
            CFDictionarySetValue(properties, kIOPMAssertionNameKey, CFSTR("Awake: Battery Closed-Lid Keep Awake"));
            CFDictionarySetValue(properties, kIOPMAssertionLevelKey, levelNumber);
            CFDictionarySetValue(properties, CFSTR("AppliesToLimitedPower"), kCFBooleanTrue);

            IOPMAssertionID assertionID = 0;
            IOReturn result = IOPMAssertionCreateWithProperties(properties, &assertionID);
            CFRelease(properties);
            CFRelease(levelNumber);
            if (result != kIOReturnSuccess || assertionID == 0) {
                fprintf(stderr, "limited-power assertion failed: 0x%x", result);
                return 9;
            }

            while (!shouldStop && getppid() == awakePID) sleep(1);
            IOPMAssertionRelease(assertionID);
            return 0;
        }

        int main(int argc, char **argv) {
            if (argc > 1 && strcmp(argv[1], "version") == 0) {
                puts("awake-smc-10");
                return 0;
            }
            if (argc > 1 && strcmp(argv[1], "hold-sleep") == 0) {
                return holdBatterySleepAssertion();
            }
            const char *mode = argc > 1 ? argv[1] : "auto";
            if (strcmp(mode, "max") != 0 && strcmp(mode, "aggressive") != 0 && strcmp(mode, "moderate") != 0 && strcmp(mode, "auto") != 0) return 64;
            bool watchParent = argc > 2 && strcmp(argv[2], "watch-parent") == 0;

            // Handlers are installed before any hardware write so that a stop
            // request or a dead parent can still roll the fans back to system
            // control instead of leaving them pinned in manual mode.
            signal(SIGPIPE, SIG_IGN);
            signal(SIGTERM, handleStopSignal);
            signal(SIGINT, handleStopSignal);
            expectedParentPID = getppid();
            if (expectedParentPID <= 1) return 3;

            io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
            if (!service) service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
            if (!service) return 1;
            io_connect_t connection = 0;
            kern_return_t openResult = IOServiceOpen(service, mach_task_self(), 0, &connection);
            IOObjectRelease(service);
            if (openResult != KERN_SUCCESS) return 2;

            uint8_t fanCountBytes[32] = {0};
            uint32_t fanCountSize = 0;
            if (!readKey(connection, "FNum", fanCountBytes, &fanCountSize) ||
                fanCountSize != 1 || fanCountBytes[0] == 0 || fanCountBytes[0] > 10) {
                fprintf(stderr, "invalid FNum");
                IOServiceClose(connection);
                return 4;
            }
            int fanCount = fanCountBytes[0];

            if (strcmp(mode, "auto") == 0) {
                bool success = true;
                for (int fan = 0; fan < fanCount; ++fan) {
                    if (!restoreFanAuto(connection, fan)) success = false;
                }
                SMCParam ftstInfo = {0};
                if (keyInfo(connection, "Ftst", &ftstInfo)) {
                    uint8_t release = 0;
                    if (!writeKeyRetry(connection, "Ftst", &release, 1, 20, 50000)) {
                        fprintf(stderr, "could not set Ftst=0");
                        success = false;
                    }
                }
                IOServiceClose(connection);
                return success ? 0 : 7;
            }

            bool success = true;
            for (int fan = 0; fan < fanCount; ++fan) {
                if (shouldStop || parentDied()) {
                    fprintf(stderr, "cancelled before fan %d", fan);
                    success = false;
                    break;
                }
                char modeKey[5] = {0};
                char maxKey[] = "F0Mx";
                char targetKey[] = "F0Tg";
                maxKey[1] = targetKey[1] = (char)('0' + fan);
                if (!resolveModeKey(connection, fan, modeKey) || !engageManual(connection, modeKey)) {
                    fprintf(stderr, " (fan %d manual mode failed)", fan);
                    success = false;
                    break;
                }

                uint8_t maxBytes[32] = {0};
                uint32_t maxSize = 0;
                bool targetOK = readKey(connection, maxKey, maxBytes, &maxSize);
                float fraction = 1.0f;
                if (strcmp(mode, "aggressive") == 0) fraction = 0.75f;
                else if (strcmp(mode, "moderate") == 0) fraction = 0.5f;
                if (targetOK && fraction < 1.0f) {
                    SMCParam maxInfo = {0};
                    targetOK = keyInfo(connection, maxKey, &maxInfo);
                    if (targetOK && maxInfo.dataType == fourCC("flt ") && maxSize == 4) {
                        float rpm = 0;
                        memcpy(&rpm, maxBytes, sizeof(rpm));
                        rpm *= fraction;
                        memcpy(maxBytes, &rpm, sizeof(rpm));
                    } else if (targetOK && maxInfo.dataType == fourCC("fpe2") && maxSize == 2) {
                        uint16_t raw = ((uint16_t)maxBytes[0] << 8) | maxBytes[1];
                        raw = (uint16_t)((float)raw * fraction);
                        maxBytes[0] = (uint8_t)(raw >> 8);
                        maxBytes[1] = (uint8_t)raw;
                    } else {
                        targetOK = false;
                    }
                }
                targetOK = targetOK &&
                           writeKeyRetry(connection, targetKey, maxBytes, maxSize, 10, 50000);
                if (!targetOK) {
                    fprintf(stderr, "could not set %s", targetKey);
                    success = false;
                    break;
                }
            }
            if (!success) rollbackToAuto(connection, fanCount);
            if (success && watchParent) {
                if (shouldStop || parentDied()) {
                    rollbackToAuto(connection, fanCount);
                    IOServiceClose(connection);
                    return 5;
                }
                puts("READY");
                fflush(stdout);
                while (!shouldStop && getppid() == expectedParentPID) sleep(1);
                rollbackToAuto(connection, fanCount);
            }
            IOServiceClose(connection);
            return success ? 0 : 6;
        }
        """
    }
}
