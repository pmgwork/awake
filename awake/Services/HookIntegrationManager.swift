//
//  HookIntegrationManager.swift
//  Awake
//

import Foundation
import Security
import Combine

public enum HookIntegrationStatus: String, Sendable {
    case unlinked
    case linked
    case needsRepair
    case unverified

    public var label: String {
        switch self {
        case .unlinked: return L10n.string("Not linked")
        case .linked: return L10n.string("Linked")
        case .needsRepair: return L10n.string("Needs repair")
        case .unverified: return L10n.string("Not tested")
        }
    }
}

@MainActor
public final class HookIntegrationManager: ObservableObject {
    public static let shared = HookIntegrationManager()

    @Published public private(set) var statuses: [AgentProvider: HookIntegrationStatus] = [:]
    @Published public private(set) var isWorking = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var toolAvailability: [AgentProvider: Bool] = [:]

    private static let ownerMarker = "pmgwork.awake"
    private let fileManager: FileManager
    private let settings: SettingsStore
    private let homeURL: URL

    public init(
        fileManager: FileManager = .default,
        settings: SettingsStore? = nil,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.settings = settings ?? .shared
        self.homeURL = homeURL
        refreshStatuses()
    }

    public func status(for provider: AgentProvider) -> HookIntegrationStatus {
        statuses[provider] ?? .unlinked
    }

    public func isToolInstalled(_ provider: AgentProvider) -> Bool {
        toolAvailability[provider] ?? false
    }

    public func install(_ provider: AgentProvider) {
        perform {
            let bridge = try installBridge()
            if provider == .openCode {
                try installOpenCodePlugin(bridgeURL: bridge)
            } else {
                try mergeHookConfiguration(for: provider, bridgeURL: bridge)
            }
            settings.clearProviderTest(provider)
        }
    }

    public func uninstall(_ provider: AgentProvider) {
        perform {
            if provider == .openCode {
                try uninstallOpenCodePlugin()
            } else {
                try removeOwnedHooks(for: provider)
            }
            settings.clearProviderTest(provider)
            if !AgentProvider.allCases.contains(where: { installedEntryExists(for: $0) }) {
                try? fileManager.removeItem(at: bridgeDestinationURL)
            }
        }
    }

    public func test(_ provider: AgentProvider) {
        perform {
            guard bridgeIsValid else { throw IntegrationError.bridgeUnavailable }
            let sessionID = "\(AgentHookEvent.integrationTestSessionIDPrefix)\(UUID().uuidString)"
            try runBridge(provider: provider, sessionID: sessionID, state: .active, reason: "integration-test")
            let found = AgentSessionStore.shared.loadValidEvents(cleaningInvalidFiles: false).contains {
                $0.provider == provider && $0.sessionID == sessionID && $0.state == .active
            }
            guard found else { throw IntegrationError.testEventNotReceived }
            try runBridge(provider: provider, sessionID: sessionID, state: .idle, reason: "integration-test-complete")
            // Remove the synthetic session explicitly so no residue depends on
            // monitor poll timing. The monitor also ignores test traffic, so
            // this can never auto-start Keep Awake.
            AgentSessionStore.shared.remove(provider: provider, sessionID: sessionID)
            settings.markProviderTested(provider)
            AgentEventMonitor.shared.reloadNow()
        }
    }

    public func refreshStatuses() {
        refreshToolAvailability()
        var result: [AgentProvider: HookIntegrationStatus] = [:]
        for provider in AgentProvider.allCases {
            let hasEntry = installedEntryExists(for: provider)
            if !hasEntry {
                result[provider] = .unlinked
            } else if !configurationIsValid(for: provider)
                        || !entryReferencesCurrentPath(for: provider)
                        || !bridgeIsValid
                        || (provider == .openCode && !openCodePluginIsValid) {
                result[provider] = .needsRepair
            } else if settings.providerLastTestedAt[provider] == nil {
                result[provider] = .unverified
            } else {
                result[provider] = .linked
            }
        }
        statuses = result
    }

    private func perform(_ operation: () throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        do {
            try operation()
        } catch {
            lastError = error.localizedDescription
            NSLog("[HookIntegrationManager] %@", error.localizedDescription)
        }
        isWorking = false
        refreshStatuses()
    }

    private var awakeSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Awake", isDirectory: true)
    }

    private var bridgeDestinationURL: URL {
        awakeSupportURL.appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("AwakeHookBridge", isDirectory: false)
    }

    private var openCodePluginURL: URL {
        openCodePluginDirectoryURL.appendingPathComponent("index.ts", isDirectory: false)
    }

    private var openCodePluginDirectoryURL: URL {
        awakeSupportURL.appendingPathComponent("integrations/opencode", isDirectory: true)
    }

    private var bridgeIsValid: Bool {
        guard fileManager.isExecutableFile(atPath: bridgeDestinationURL.path) else { return false }
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bridgeDestinationURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
    }

    private func installBridge() throws -> URL {
        let bundledURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/AwakeHookBridge", isDirectory: false)
        guard fileManager.fileExists(atPath: bundledURL.path) else {
            throw IntegrationError.bundledBridgeMissing
        }
        let directory = bridgeDestinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".AwakeHookBridge.\(UUID().uuidString)")
        try fileManager.copyItem(at: bundledURL, to: temporary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: bridgeDestinationURL.path) {
            _ = try fileManager.replaceItemAt(bridgeDestinationURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: bridgeDestinationURL)
        }
        guard bridgeIsValid else { throw IntegrationError.invalidBridgeSignature }
        return bridgeDestinationURL
    }

    private func configurationURL(for provider: AgentProvider) -> URL {
        switch provider {
        case .codex:
            return homeURL.appendingPathComponent(".codex/hooks.json")
        case .claude:
            return homeURL.appendingPathComponent(".claude/settings.json")
        case .antigravity:
            return homeURL.appendingPathComponent(".gemini/config/hooks.json")
        case .openCode:
            let directory = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map(URL.init(fileURLWithPath:))
                ?? homeURL.appendingPathComponent(".config", isDirectory: true)
            let base = directory.appendingPathComponent("opencode", isDirectory: true)
            let jsonc = base.appendingPathComponent("opencode.jsonc")
            return fileManager.fileExists(atPath: jsonc.path) ? jsonc : base.appendingPathComponent("opencode.json")
        }
    }

    private func mergeHookConfiguration(for provider: AgentProvider, bridgeURL: URL) throws {
        let url = configurationURL(for: provider)
        var root = try readJSONObject(at: url)
        if provider == .antigravity {
            root[Self.ownerMarker] = [
                "PreInvocation": [[
                    "type": "command",
                    "command": command(bridgeURL, provider: provider, event: "PreInvocation"),
                    "timeout": 2,
                ]],
                "PostToolUse": [[
                    "matcher": "*",
                    "hooks": [[
                        "type": "command",
                        "command": command(bridgeURL, provider: provider, event: "PostToolUse"),
                        "timeout": 2,
                    ]],
                ]],
                "Stop": [[
                    "type": "command",
                    "command": command(bridgeURL, provider: provider, event: "Stop"),
                    "timeout": 2,
                ]],
            ]
        } else {
            let hooksValue = root["hooks"]
            guard hooksValue == nil || hooksValue is [String: Any] else {
                throw IntegrationError.invalidConfiguration(url.path)
            }
            var hooks = hooksValue as? [String: Any] ?? [:]
            let eventNames: [String]
            switch provider {
            case .codex:
                eventNames = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "Interrupt", "SessionEnd"]
            case .claude:
                eventNames = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "StopFailure", "SessionEnd"]
            default:
                eventNames = []
            }
            for eventName in eventNames {
                let groupsValue = hooks[eventName]
                guard groupsValue == nil || groupsValue is [[String: Any]] else {
                    throw IntegrationError.invalidConfiguration(url.path)
                }
                var groups = groupsValue as? [[String: Any]] ?? []
                groups = removingOwnedGroups(groups)
                groups.append([
                    "hooks": [[
                        "type": "command",
                        "command": command(bridgeURL, provider: provider),
                        "timeout": eventName == "SessionEnd" || eventName == "Interrupt" ? 1 : 2,
                    ]],
                ])
                hooks[eventName] = groups
            }
            if provider == .claude {
                let groupsValue = hooks["Notification"]
                guard groupsValue == nil || groupsValue is [[String: Any]] else {
                    throw IntegrationError.invalidConfiguration(url.path)
                }
                var groups = groupsValue as? [[String: Any]] ?? []
                groups = removingOwnedGroups(groups)
                groups.append([
                    "matcher": "idle_prompt",
                    "hooks": [[
                        "type": "command",
                        "command": command(bridgeURL, provider: provider),
                        "timeout": 2,
                    ]],
                ])
                hooks["Notification"] = groups
            }
            root["hooks"] = hooks
        }
        try writeJSONObject(root, to: url)
    }

    private func removeOwnedHooks(for provider: AgentProvider) throws {
        let url = configurationURL(for: provider)
        guard fileManager.fileExists(atPath: url.path) else { return }
        var root = try readJSONObject(at: url)
        if provider == .antigravity {
            root.removeValue(forKey: Self.ownerMarker)
        } else if var hooks = root["hooks"] as? [String: Any] {
            for key in Array(hooks.keys) {
                guard let groups = hooks[key] as? [[String: Any]] else { continue }
                let cleaned = removingOwnedGroups(groups)
                if cleaned.isEmpty { hooks.removeValue(forKey: key) }
                else { hooks[key] = cleaned }
            }
            if hooks.isEmpty { root.removeValue(forKey: "hooks") }
            else { root["hooks"] = hooks }
        }
        try writeJSONObject(root, to: url)
    }

    private func removingOwnedGroups(_ groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
            let remaining = handlers.filter {
                guard let command = $0["command"] as? String else { return true }
                return !command.contains("--owner \(Self.ownerMarker)")
            }
            guard !remaining.isEmpty else { return nil }
            var copy = group
            copy["hooks"] = remaining
            return copy
        }
    }

    private func command(_ bridgeURL: URL, provider: AgentProvider, event: String? = nil) -> String {
        var parts = [bridgeURL.path, "--provider", provider.rawValue, "--owner", Self.ownerMarker]
        if let event { parts += ["--event", event] }
        return parts.map(shellQuoteIfNeeded).joined(separator: " ")
    }

    private func shellQuoteIfNeeded(_ value: String) -> String {
        value.contains("/") || value.contains(" ") || value.contains("'") ? shellQuote(value) : value
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func installOpenCodePlugin(bridgeURL: URL) throws {
        guard let sourceURL = Bundle.main.url(forResource: "OpenCodeAwakePlugin", withExtension: "ts", subdirectory: "Hooks")
                ?? Bundle.main.url(forResource: "OpenCodeAwakePlugin", withExtension: "ts") else {
            throw IntegrationError.pluginResourceMissing
        }
        var source = try String(contentsOf: sourceURL, encoding: .utf8)
        source = source.replacingOccurrences(of: "__AWAKE_BRIDGE_PATH__", with: javaScriptEscaped(bridgeURL.path))
        try atomicWrite(Data(source.utf8), to: openCodePluginURL, permissions: 0o600)
        // V2 beta loaders require a directory. The manifest also lets V1
        // resolve that directory to the shared entrypoint.
        let manifest = """
        {"name":"awake-opencode-plugin","version":"1.0.0","private":true,"type":"module","main":"./index.ts","exports":"./index.ts"}
        """
        try atomicWrite(Data(manifest.utf8), to: openCodePluginDirectoryURL.appendingPathComponent("package.json"), permissions: 0o600)

        let configURL = configurationURL(for: .openCode)
        var root = try readJSONObject(at: configURL, allowsJSONC: true)
        // V1 reads plugin; V2 also accepts it. If native V2 plugins already
        // exists, keep our entry there too because that field takes precedence.
        for key in ["plugin", "plugins"] {
            let value = root[key]
            guard value == nil || value is [Any] else {
                throw IntegrationError.invalidConfiguration(configURL.path)
            }
            if key == "plugins" && value == nil { continue }
            var plugins = value as? [Any] ?? []
            plugins.removeAll { isOwnedOpenCodePlugin($0) }
            if key == "plugins" && plugins.isEmpty {
                root.removeValue(forKey: key)
                continue
            }
            plugins.append(openCodePluginDirectoryURL.absoluteString)
            root[key] = plugins
        }
        try writeJSONObject(root, to: configURL)
    }

    private func uninstallOpenCodePlugin() throws {
        let configURL = configurationURL(for: .openCode)
        if fileManager.fileExists(atPath: configURL.path) {
            var root = try readJSONObject(at: configURL, allowsJSONC: true)
            for key in ["plugin", "plugins"] {
                if var plugins = root[key] as? [Any] {
                    plugins.removeAll { isOwnedOpenCodePlugin($0) }
                    if plugins.isEmpty { root.removeValue(forKey: key) }
                    else { root[key] = plugins }
                }
            }
            try writeJSONObject(root, to: configURL)
        }
        try? fileManager.removeItem(at: openCodePluginDirectoryURL)
    }

    private func isOwnedOpenCodePlugin(_ value: Any) -> Bool {
        guard let path = value as? String else { return false }
        return [openCodePluginDirectoryURL.path, openCodePluginDirectoryURL.absoluteString, openCodePluginURL.path,
                openCodePluginURL.absoluteString].contains(path)
    }

    private func installedEntryExists(for provider: AgentProvider) -> Bool {
        let url = configurationURL(for: provider)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return false }
        // JSONSerialization escapes "/" as "\/", so normalize before path matching.
        // The owner marker itself contains no slashes and is unaffected.
        let normalized = text.replacingOccurrences(of: "\\/", with: "/")
        if provider == .openCode {
            return normalized.contains(openCodePluginDirectoryURL.path)
                || normalized.contains(openCodePluginURL.absoluteString)
                || normalized.contains(openCodePluginDirectoryURL.absoluteString)
        }
        return normalized.contains("--owner \(Self.ownerMarker)") || (provider == .antigravity && normalized.contains("\"\(Self.ownerMarker)\""))
    }

    private func configurationIsValid(for provider: AgentProvider) -> Bool {
        let url = configurationURL(for: provider)
        return (try? readJSONObject(at: url, allowsJSONC: provider == .openCode)) != nil
    }

    private func entryReferencesCurrentPath(for provider: AgentProvider) -> Bool {
        let url = configurationURL(for: provider)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        // Written JSON escapes "/" as "\/", so compare against the unescaped form.
        let normalized = text.replacingOccurrences(of: "\\/", with: "/")
        let expected = provider == .openCode ? openCodePluginDirectoryURL.path : bridgeDestinationURL.path
        return normalized.contains(expected)
            || (provider == .openCode && normalized.contains(openCodePluginURL.absoluteString))
            || (provider == .openCode && normalized.contains(openCodePluginDirectoryURL.absoluteString))
    }

    private var openCodePluginIsValid: Bool {
        guard let manifest = try? readJSONObject(at: openCodePluginDirectoryURL.appendingPathComponent("package.json")),
              manifest["main"] as? String == "./index.ts" else { return false }
        guard let source = try? String(contentsOf: openCodePluginURL, encoding: .utf8) else { return false }
        // Plugins written by older builds escaped "/" as "\/" via
        // JSONSerialization. Normalize so existing installs heal on refresh.
        let normalized = source.replacingOccurrences(of: "\\/", with: "/")
        // Require the V2 event payload reader so older templates that silently
        // ignored session events are reinstalled via Repair.
        return normalized.contains("pmgwork.awake")
            && normalized.contains("AwakePlugin")
            && normalized.contains("event.data ?? event.properties")
            && normalized.contains("async server()")
            && normalized.contains("session.execution.started")
            && normalized.contains(bridgeDestinationURL.path)
            && !normalized.contains("__AWAKE_BRIDGE_PATH__")
    }

    private func refreshToolAvailability() {
        var result: [AgentProvider: Bool] = [:]
        for provider in AgentProvider.allCases {
            result[provider] = provider.toolNames.contains(where: toolExists(named:))
        }
        toolAvailability = result
    }

    private func toolExists(named name: String) -> Bool {
        for directory in Self.toolSearchDirectories(homeURL: homeURL) {
            let url = directory.appendingPathComponent(name, isDirectory: false)
            if fileManager.isExecutableFile(atPath: url.path) { return true }
        }
        return false
    }

    private static func toolSearchDirectories(homeURL: URL) -> [URL] {
        // GUI apps often launch with a minimal PATH, so well-known install
        // locations are checked in addition to PATH entries.
        var seen = Set<String>()
        var result: [URL] = []
        func add(_ url: URL) {
            let path = url.path
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            result.append(url)
        }
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for component in pathValue.split(separator: ":") {
            add(URL(fileURLWithPath: String(component), isDirectory: true))
        }
        add(URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true))
        add(URL(fileURLWithPath: "/usr/local/bin", isDirectory: true))
        add(homeURL.appendingPathComponent(".local/bin", isDirectory: true))
        // Tool-specific default locations and version-manager shims, which are
        // typically on PATH in a terminal but not for GUI-launched apps.
        add(homeURL.appendingPathComponent(".opencode/bin", isDirectory: true))
        add(homeURL.appendingPathComponent(".proto/shims", isDirectory: true))
        add(homeURL.appendingPathComponent(".local/share/mise/shims", isDirectory: true))
        add(homeURL.appendingPathComponent(".volta/bin", isDirectory: true))
        add(homeURL.appendingPathComponent(".bun/bin", isDirectory: true))
        return result
    }

    private func runBridge(provider: AgentProvider, sessionID: String, state: AgentSessionState, reason: String) throws {
        let process = Process()
        process.executableURL = bridgeDestinationURL
        process.arguments = [
            "--provider", provider.rawValue,
            "--session-id", sessionID,
            "--state", state.rawValue,
            "--reason", reason,
            "--owner", Self.ownerMarker,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw IntegrationError.bridgeFailed }
    }

    private func readJSONObject(at url: URL, allowsJSONC: Bool = false) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let parseData: Data
        if allowsJSONC, let text = String(data: data, encoding: .utf8) {
            parseData = Data(stripJSONC(text).utf8)
        } else {
            parseData = data
        }
        guard let object = try JSONSerialization.jsonObject(with: parseData) as? [String: Any] else {
            throw IntegrationError.invalidConfiguration(url.path)
        }
        return object
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else { throw IntegrationError.invalidConfiguration(url.path) }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
        let backup = url.appendingPathExtension("awake-backup")
        do {
            try atomicWrite(data, to: url, permissions: 0o600, createsBackup: true)
            _ = try readJSONObject(at: url, allowsJSONC: url.pathExtension == "jsonc")
        } catch {
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: url)
                try? fileManager.copyItem(at: backup, to: url)
            }
            throw error
        }
    }

    private func atomicWrite(_ data: Data, to url: URL, permissions: Int, createsBackup: Bool = false) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if createsBackup, fileManager.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("awake-backup")
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: url, to: backup)
        }
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }

    private func javaScriptEscaped(_ value: String) -> String {
        // Escape for a double-quoted JavaScript string literal. Unlike
        // JSONSerialization, a forward slash must NOT be escaped: the written
        // plugin is later validated with a raw-path substring check.
        var result = ""
        result.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    private func stripJSONC(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if inString {
                result.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                index = next
                continue
            }
            if character == "\"" {
                inString = true
                result.append(character)
                index = next
                continue
            }
            if character == "/", next < text.endIndex, text[next] == "/" {
                index = text.index(after: next)
                while index < text.endIndex, text[index] != "\n" { index = text.index(after: index) }
                continue
            }
            if character == "/", next < text.endIndex, text[next] == "*" {
                index = text.index(after: next)
                while index < text.endIndex {
                    let following = text.index(after: index)
                    if text[index] == "*", following < text.endIndex, text[following] == "/" {
                        index = text.index(after: following)
                        break
                    }
                    index = following
                }
                continue
            }
            result.append(character)
            index = next
        }
        // JSONC permits trailing commas. Removing only commas followed by a
        // closing array/object is safe after comments and strings are handled.
        return result.replacingOccurrences(of: ",\\s*([}\\]])", with: "$1", options: .regularExpression)
    }

    public enum IntegrationError: LocalizedError {
        case bundledBridgeMissing, invalidBridgeSignature, bridgeUnavailable, bridgeFailed
        case pluginResourceMissing, testEventNotReceived, invalidConfiguration(String)

        public var errorDescription: String? {
            switch self {
            case .bundledBridgeMissing: return L10n.string("The bundled AwakeHookBridge is missing.")
            case .invalidBridgeSignature: return L10n.string("AwakeHookBridge failed signature validation.")
            case .bridgeUnavailable: return L10n.string("AwakeHookBridge is not installed or is damaged.")
            case .bridgeFailed: return L10n.string("AwakeHookBridge did not complete successfully.")
            case .pluginResourceMissing: return L10n.string("The OpenCode plugin resource is missing.")
            case .testEventNotReceived: return L10n.string("Awake did not receive the integration test event.")
            case let .invalidConfiguration(path): return L10n.format("The provider configuration is invalid: %@", path)
            }
        }
    }
}
