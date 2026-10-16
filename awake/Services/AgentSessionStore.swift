//
//  AgentSessionStore.swift
//  Awake
//

import Foundation
import CryptoKit
import Darwin

public nonisolated final class AgentSessionStore: @unchecked Sendable {
    public static let shared = AgentSessionStore()

    /// Safety net for orphaned non-terminal sessions (e.g. a missed Stop event
    /// combined with an unverifiable sourcePID). Deliberately generous: short
    /// TTLs are forbidden because long model runs can go hook-silent, so this
    /// only bounds sessions with zero events for a full day. Any fresh event
    /// for the session re-asserts it.
    public static let orphanSessionTTL: TimeInterval = 24 * 60 * 60

    public let directoryURL: URL
    private let fileManager: FileManager
    private let cacheLock = NSLock()
    private struct CachedEvent {
        let data: Data
        let event: AgentHookEvent
    }
    private var cachedEvents: [URL: CachedEvent] = [:]

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
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        // Avoid emitting a filesystem change on every poll of our own directory.
        let permissions = try? fileManager.attributesOfItem(atPath: directoryURL.path)[.posixPermissions] as? NSNumber
        if permissions?.intValue != 0o700 {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        }
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

    public func loadValidEvents(
        cleaningInvalidFiles: Bool = true,
        now: Date = Date(),
        reloadingFiles: Bool = true
    ) -> [AgentHookEvent] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if reloadingFiles {
            guard (try? prepareDirectory()) != nil else { return [] }
        }
        let urls = reloadingFiles ? ((try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []) : Array(cachedEvents.keys)
        let existingURLs = Set(urls)
        cachedEvents = cachedEvents.filter { existingURLs.contains($0.key) }
        var newestBySession: [String: AgentHookEvent] = [:]
        for url in urls where url.pathExtension == "json" {
            let snapshot = reloadingFiles ? (try? readCached(url)) : cachedEvents[url]?.event
            guard let event = snapshot,
                  event.schemaVersion == AgentHookEvent.currentSchemaVersion,
                  !event.sessionID.isEmpty else {
                cachedEvents.removeValue(forKey: url)
                if cleaningInvalidFiles { try? fileManager.removeItem(at: url) }
                continue
            }
            if (event.state == .active || event.state == .waitingForInput),
               let pid = event.sourcePID,
               !Self.processIsSame(pid: pid, expectedStartTime: event.sourceProcessStartTime) {
                if cleaningInvalidFiles { removeIfUnchanged(url: url, event: event) }
                continue
            }
            if (event.state == .active || event.state == .waitingForInput),
               now.timeIntervalSince(event.occurredAt) > Self.orphanSessionTTL {
                if cleaningInvalidFiles { removeIfUnchanged(url: url, event: event) }
                continue
            }
            if let current = newestBySession[event.sessionKey], current.occurredAt > event.occurredAt {
                continue
            }
            newestBySession[event.sessionKey] = event
        }
        return newestBySession.values.sorted { $0.occurredAt < $1.occurredAt }
    }

    /// Compare the bytes, rather than timestamps: atomic replacements can have
    /// equal sizes and timestamps. Unchanged snapshots never reparse JSON/dates.
    private func readCached(_ url: URL) throws -> AgentHookEvent {
        let data = try Data(contentsOf: url)
        guard data.count <= 64 * 1024 else { throw StoreError.invalidEvent }
        if let cached = cachedEvents[url], cached.data == data { return cached.event }
        let event = try decode(data)
        cachedEvents[url] = CachedEvent(data: data, event: event)
        return event
    }

    public func remove(provider: AgentProvider, sessionID: String) {
        try? fileManager.removeItem(at: fileURL(provider: provider, sessionID: sessionID))
    }

    /// Deletes an expired snapshot under the bridge's write lock, preserving
    /// a newer event that arrived while the cleanup pass was running.
    private func removeIfUnchanged(url: URL, event: AgentHookEvent) {
        let lockURL = directoryURL.appendingPathComponent(".write.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return }
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        guard flock(descriptor, LOCK_EX) == 0 else { return }
        // Dates round-trip through ISO8601 with millisecond precision, so a
        // freshly-created event can differ from its stored copy by <1 ms.
        guard let current = try? read(url),
              current.state == event.state,
              abs(current.occurredAt.timeIntervalSince(event.occurredAt)) < 0.001 else { return }
        try? fileManager.removeItem(at: url)
    }

    public func fileURL(provider: AgentProvider, sessionID: String) -> URL {
        let key = "\(provider.rawValue)\u{0}\(sessionID)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent("\(digest).json", isDirectory: false)
    }

    private func read(_ url: URL) throws -> AgentHookEvent {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= 64 * 1024 else { throw StoreError.invalidEvent }
        return try decode(data)
    }

    private func decode(_ data: Data) throws -> AgentHookEvent {
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
        dateFormatterLock.lock()
        defer { dateFormatterLock.unlock() }
        return fractionalFormatter.string(from: date)
    }

    private static func iso8601Date(from value: String) -> Date? {
        dateFormatterLock.lock()
        defer { dateFormatterLock.unlock() }
        return fractionalFormatter.date(from: value) ?? wholeSecondsFormatter.date(from: value)
    }

    private static let dateFormatterLock = NSLock()
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let wholeSecondsFormatter = ISO8601DateFormatter()

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
