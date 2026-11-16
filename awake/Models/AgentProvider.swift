//
//  AgentProvider.swift
//  Awake
//

import Foundation

public nonisolated enum AgentProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    // Declaration order is the display order.
    case codex
    case claude
    case antigravity
    case openCode = "opencode"

    public var id: String { rawValue }

    public var sortIndex: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .openCode: return "OpenCode"
        case .antigravity: return "Antigravity"
        }
    }

    public var integrationKind: String {
        self == .openCode ? L10n.string("Plugin") : L10n.string("Hook")
    }

    /// Command names used to detect a local install of the provider tool.
    public var toolNames: [String] {
        switch self {
        case .codex: return ["codex"]
        case .claude: return ["claude"]
        case .openCode: return ["opencode", "opencode2"]
        case .antigravity: return ["antigravity", "agy"]
        }
    }

    /// Bundle identifiers of desktop apps that share the provider's hook integration.
    public var applicationBundleIdentifiers: [String] {
        switch self {
        case .antigravity: return ["com.google.antigravity"]
        case .codex, .claude, .openCode: return []
        }
    }

    /// Application bundle names checked under `/Applications` and `~/Applications`.
    public var applicationNames: [String] {
        switch self {
        case .antigravity: return ["Antigravity.app"]
        case .codex, .claude, .openCode: return []
        }
    }

    public static func infer(name: String, processNames: [String]) -> AgentProvider? {
        let candidates = Set(([name] + processNames).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        if !candidates.isDisjoint(with: ["codex"]) { return .codex }
        if !candidates.isDisjoint(with: ["claude", "claude code"]) { return .claude }
        if !candidates.isDisjoint(with: ["opencode", "opencode2"]) { return .openCode }
        if !candidates.isDisjoint(with: ["antigravity", "agy"]) { return .antigravity }
        return nil
    }
}
