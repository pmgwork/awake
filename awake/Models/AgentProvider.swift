//
//  AgentProvider.swift
//  Awake
//

import Foundation

public nonisolated enum AgentProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case openCode = "opencode"
    case antigravity

    public var id: String { rawValue }

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
