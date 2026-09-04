//
//  AgentSessionStore.swift
//  Awake
//

import Foundation
import CryptoKit
import Darwin

public nonisolated final class AgentSessionStore: @unchecked Sendable {
    public static let shared = AgentSessionStore()

    public let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directoryURL = applicationSupport
                .appendingPathComponent("Awake", isDirectory: true)
                .appendingPathComponent("agent-sessions", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        }
    }

    public func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    @discardableResult
    public func save(_ event: AgentHookEvent) throws -> URL {
        guard event.schemaVersion == AgentHookEvent.currentSchemaVersion,
              !event.sessionID.isEmpty else {
            throw StoreError.invalidEvent
        }
        try prepareDirectory()
        let url = fileURL(provider: event.provider, sessionID: event.sessionID)
        if let existing = try? read(url), existing.occurredAt > event.occurredAt {
            return url
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601String(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    public func loadValidEvents(cleaningInvalidFiles: Bool = true) -> [AgentHookEvent] {
        guard (try? prepareDirectory()) != nil else { return [] }
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var newestBySession: [String: AgentHookEvent] = [:]
        for url in urls where url.pathExtension == "json" {
            guard let event = try? read(url),
                  event.schemaVersion == AgentHookEvent.currentSchemaVersion,
                  !event.sessionID.isEmpty else {
                if cleaningInvalidFiles { try? fileManager.removeItem(at: url) }
                continue
            }
            if (event.state == .active || event.state == .waitingForInput),
               let pid = event.sourcePID,
               !Self.processIsSame(pid: pid, expectedStartTime: event.sourceProcessStartTime) {
                if cleaningInvalidFiles { try? fileManager.removeItem(at: url) }
                continue
            }
            if let current = newestBySession[event.sessionKey], current.occurredAt > event.occurredAt {
                continue
            }
            newestBySession[event.sessionKey] = event
        }
        return newestBySession.values.sorted { $0.occurredAt < $1.occurredAt }
    }

    public func remove(_ event: AgentHookEvent) {
        try? fileManager.removeItem(at: fileURL(provider: event.provider, sessionID: event.sessionID))
    }

    public func removeAll() {
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return
        }
        for url in urls where url.pathExtension == "json" {
            try? fileManager.removeItem(at: url)
        }
    }

    public func fileURL(provider: AgentProvider, sessionID: String) -> URL {
        let key = "\(provider.rawValue)\u{0}\(sessionID)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent("\(digest).json", isDirectory: false)
    }

    private func read(_ url: URL) throws -> AgentHookEvent {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= 64 * 1024 else { throw StoreError.invalidEvent }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = Self.iso8601Date(from: value) else { throw StoreError.invalidEvent }
            return date
        }
        return try decoder.decode(AgentHookEvent.self, from: data)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func iso8601Date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func processIsSame(pid: Int32, expectedStartTime: TimeInterval?) -> Bool {
        guard pid > 1, kill(pid, 0) == 0 || errno == EPERM else { return false }
        guard let expectedStartTime else { return true }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        let actual = TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        return abs(actual - expectedStartTime) < 0.001
    }

    public enum StoreError: Error {
        case invalidEvent
    }
}
