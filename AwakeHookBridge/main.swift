import Foundation
import CryptoKit
import Darwin
import IOKit
import IOKit.pwr_mgt

// The parent keeps stdin open for the duration of a closed-display session.
// EOF also arrives if Awake crashes, so the override can always be released.
private enum ClamshellLease {
    static func run() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return }
        defer { IOServiceClose(connection) }

        func setDisabled(_ disabled: Bool) -> Bool {
            var value: UInt64 = disabled ? 1 : 0
            return withUnsafePointer(to: &value) { pointer in
                IOConnectCallScalarMethod(connection, UInt32(kPMSetClamshellSleepState), pointer, 1, nil, nil)
            } == kIOReturnSuccess
        }

        guard setDisabled(true) else { return }
        defer { _ = setDisabled(false) }
        FileHandle.standardOutput.write(Data("ready\n".utf8))

        var byte: UInt8 = 0
        // The parent sends a byte when stopping normally; EOF means it died.
        while read(STDIN_FILENO, &byte, 1) < 0 && errno == EINTR {}
    }
}

private enum Provider: String, Codable {
    case codex, claude, opencode, antigravity
}

private enum SessionState: String, Codable {
    case active, waitingForInput, idle, stale
}

private struct StoredEvent: Codable {
    let schemaVersion: Int
    let provider: Provider
    let sessionID: String
    let turnID: String?
    let state: SessionState
    let reason: String
    let occurredAt: Date
    let sourcePID: Int32?
    let sourceProcessStartTime: TimeInterval?
}

private struct AwakeHookBridge {
    static func run() {
        if ProcessInfo.processInfo.arguments.contains("--clamshell-lease") {
            ClamshellLease.run()
            return
        }
        // A hook integration must never stop or fail the provider. All malformed
        // input and filesystem errors intentionally become a successful no-op.
        autoreleasepool {
            let arguments = parseArguments(ProcessInfo.processInfo.arguments)
            let eventName = arguments["event"]
            defer { writeNeutralProviderResponse(provider: arguments["provider"], eventName: eventName) }
            guard let providerValue = arguments["provider"],
                  let provider = Provider(rawValue: providerValue) else { return }

            let input = readInput()
            guard let normalized = normalize(
                provider: provider,
                explicitEvent: eventName,
                arguments: arguments,
                input: input
            ) else { return }
            try? save(normalized)
        }
    }

    private static func normalize(
        provider: Provider,
        explicitEvent: String?,
        arguments: [String: String],
        input: [String: Any]
    ) -> StoredEvent? {
        let eventName = explicitEvent
            ?? input["hook_event_name"] as? String
            ?? input["hookEventName"] as? String
            ?? arguments["reason"]
            ?? "unknown"
        let sessionID = arguments["session-id"]
            ?? input["session_id"] as? String
            ?? input["sessionID"] as? String
            ?? input["conversationId"] as? String
        guard let sessionID,
              !sessionID.isEmpty,
              sessionID.utf8.count <= 1024 else { return nil }

        let state: SessionState
        if let rawState = arguments["state"], let directState = SessionState(rawValue: rawState) {
            state = directState
        } else {
            switch provider {
            case .codex:
                switch eventName.lowercased() {
                case "userpromptsubmit", "pretooluse", "posttooluse": state = .active
                case "stop", "interrupt", "sessionend": state = .idle
                default: return nil
                }
            case .claude:
                if eventName.caseInsensitiveCompare("Notification") == .orderedSame,
                   (input["notification_type"] as? String) == "idle_prompt" {
                    state = .waitingForInput
                } else {
                    switch eventName.lowercased() {
                    case "userpromptsubmit", "pretooluse", "posttooluse": state = .active
                    case "stop", "stopfailure", "sessionend": state = .idle
                    default: return nil
                    }
                }
            case .antigravity:
                switch eventName.lowercased() {
                case "preinvocation", "pretooluse", "posttooluse": state = .active
                case "stop":
                    state = (input["fullyIdle"] as? Bool) == true ? .idle : .active
                default: return nil
                }
            case .opencode:
                guard let rawState = arguments["state"], let openCodeState = SessionState(rawValue: rawState) else {
                    return nil
                }
                state = openCodeState
            }
        }

        let date = arguments["occurred-at"].flatMap(iso8601Date(from:)) ?? Date()
        let identity = providerProcessIdentity(provider: provider)
        return StoredEvent(
            schemaVersion: 1,
            provider: provider,
            sessionID: sessionID,
            turnID: arguments["turn-id"] ?? input["turn_id"] as? String,
            state: state,
            reason: arguments["reason"] ?? eventName,
            occurredAt: date,
            sourcePID: identity?.pid,
            sourceProcessStartTime: identity?.startTime
        )
    }

    private static func save(_ event: StoredEvent) throws {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support
            .appendingPathComponent("Awake", isDirectory: true)
            .appendingPathComponent("agent-sessions", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let key = "\(event.provider.rawValue)\u{0}\(event.sessionID)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent("\(digest).json")
        let lockURL = directory.appendingPathComponent(".write.lock")
        let lockDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockDescriptor >= 0 else { return }
        defer {
            flock(lockDescriptor, LOCK_UN)
            close(lockDescriptor)
        }
        guard flock(lockDescriptor, LOCK_EX) == 0 else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = iso8601Date(from: value) else {
                throw CocoaError(.coderReadCorrupt)
            }
            return date
        }
        if let data = try? Data(contentsOf: url),
           let existing = try? decoder.decode(StoredEvent.self, from: data),
           existing.occurredAt > event.occurredAt {
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601String(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(event).write(to: url, options: .atomic)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func parseArguments(_ arguments: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--"), index + 1 < arguments.count {
                result[String(argument.dropFirst(2))] = arguments[index + 1]
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }

    private static func readInput() -> [String: Any] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty,
              data.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func writeNeutralProviderResponse(provider: String?, eventName: String?) {
        guard provider == Provider.antigravity.rawValue else { return }
        if eventName?.caseInsensitiveCompare("Stop") == .orderedSame {
            print("{\"decision\":\"\"}")
        } else {
            print("{}")
        }
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func iso8601Date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func providerProcessIdentity(provider: Provider) -> (pid: Int32, startTime: TimeInterval)? {
        let expectedNames: Set<String>
        switch provider {
        case .codex: expectedNames = ["codex"]
        case .claude: expectedNames = ["claude"]
        case .opencode: expectedNames = ["opencode", "opencode2"]
        case .antigravity: expectedNames = ["antigravity", "agy"]
        }

        var pid = getppid()
        for _ in 0..<12 where pid > 1 {
            if let identity = processIdentity(pid: pid) {
                let executable = URL(fileURLWithPath: identity.path).lastPathComponent.lowercased()
                let lowercasedPath = identity.path.lowercased()
                let arguments = processArguments(pid: pid)?.lowercased() ?? ""
                let mayBeRuntimeHost = ["node", "bun", "deno", "electron"].contains(executable)
                if expectedNames.contains(executable)
                    || expectedNames.contains(where: { lowercasedPath.contains($0) })
                    || (mayBeRuntimeHost && expectedNames.contains(where: { arguments.contains($0) })) {
                    return (pid, identity.startTime)
                }
                pid = identity.parentPID
            } else {
                break
            }
        }
        return nil
    }

    private static func processIdentity(pid: Int32) -> (path: String, parentPID: Int32, startTime: TimeInterval)? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let startTime = TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        return (String(cString: pathBuffer), Int32(info.pbi_ppid), startTime)
    }

    private static func processArguments(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &data, &size, nil, 0) == 0 else { return nil }
        return String(bytes: data.dropFirst(MemoryLayout<Int32>.size).map { $0 == 0 ? 32 : $0 }, encoding: .utf8)
    }
}

AwakeHookBridge.run()
