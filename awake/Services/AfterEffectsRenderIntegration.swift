import AppKit
import Carbon
import Combine

/// Attaches a session-scoped queue observer through Automation. No Adobe
/// installation files or project contents are written.
@MainActor
final class AfterEffectsRenderIntegration: ObservableObject {
    static let shared = AfterEffectsRenderIntegration()
    @Published private(set) var isLinked = UserDefaults.standard.bool(forKey: "afterEffectsRenderLinked")
    @Published private(set) var lastError: String?
    private var sessions: [pid_t: Session] = [:]
    private let worker = DispatchQueue(label: "pmgwork.awake.after-effects", qos: .utility)
    private var enabled = false

    private struct Session {
        let launch: Date?
        let token: String
        let directory: URL
        var attached = false
        var attempting = false
        var nextAttempt = Date.distantPast
        var control: URL { directory.appendingPathComponent("enabled") }
        var signal: URL { directory.appendingPathComponent("status.json") }
    }

    func link() {
        isLinked = true
        UserDefaults.standard.set(true, forKey: "afterEffectsRenderLinked")
        lastError = nil
        if enabled { refresh() }
    }

    func unlink() {
        isLinked = false
        UserDefaults.standard.set(false, forKey: "afterEffectsRenderLinked")
        clearSessions()
        lastError = nil
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if value && isLinked { refresh() } else { clearSessions() }
    }

    private func clearSessions() {
        for session in sessions.values { try? FileManager.default.removeItem(at: session.directory) }
        sessions = [:]
    }

    /// Called on the main thread with each render sample. A session's UUID
    /// and launch date prevent stale reports from a reused PID being accepted.
    func refresh() {
        guard enabled && isLinked else { return }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier?.hasPrefix("com.adobe.AfterEffects") == true
        }
        let live = Set(apps.map(\.processIdentifier))
        for pid in Array(sessions.keys) where !live.contains(pid) {
            if let old = sessions.removeValue(forKey: pid) { try? FileManager.default.removeItem(at: old.directory) }
        }
        for app in apps {
            let pid = app.processIdentifier
            if let old = sessions[pid], old.launch != app.launchDate {
                try? FileManager.default.removeItem(at: old.directory)
                sessions.removeValue(forKey: pid)
            }
            if sessions[pid] == nil {
                let token = UUID().uuidString
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("pmgwork.awake-ae-\(token)", isDirectory: true)
                sessions[pid] = Session(launch: app.launchDate, token: token, directory: directory)
            }
            guard var session = sessions[pid], !session.attached, !session.attempting,
                  session.nextAttempt <= Date() else { continue }
            do {
                try FileManager.default.createDirectory(at: session.directory, withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                try Data(session.token.utf8).write(to: session.control, options: .atomic)
                let script = try Self.script(control: session.control, signal: session.signal, token: session.token)
                session.attempting = true
                sessions[pid] = session
                let token = session.token
                worker.async {
                    let error = Self.send(script, to: pid)
                    Task { @MainActor in
                        guard var current = self.sessions[pid], current.token == token else { return }
                        current.attempting = false
                        current.attached = error == nil
                        // Retry busy/startup failures, but do not repeatedly ask for Automation access.
                        current.nextAttempt = Date().addingTimeInterval(error == nil ? 0 : 30)
                        self.sessions[pid] = current
                        if let error { self.lastError = error }
                        else { self.lastError = nil }
                    }
                }
            } catch { lastError = error.localizedDescription }
        }
    }

    var hasActiveRender: Bool {
        sessions.values.contains { session in
            guard let data = try? Data(contentsOf: session.signal) else { return false }
            return Self.isActiveReport(data, token: session.token)
        }
    }

    nonisolated static func isActiveReport(_ data: Data, token: String) -> Bool {
        struct Report: Decodable { let token: String; let active: Bool }
        guard let report = try? JSONDecoder().decode(Report.self, from: data) else { return false }
        // No heartbeat expiry: AE can block its script timer for a long frame.
        return report.token == token && report.active
    }

    nonisolated static func script(control: URL, signal: URL, token: String) throws -> String {
        guard let url = Bundle.main.url(forResource: "after-effects-monitor", withExtension: "jsx") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let config = try JSONSerialization.data(withJSONObject: [
            "controlPath": control.path, "signalPath": signal.path, "token": token,
        ], options: [.sortedKeys])
        return try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "__AWAKE_CONFIG__", with: String(decoding: config, as: UTF8.self))
    }

    nonisolated private static func send(_ script: String, to pid: pid_t) -> String? {
        let event = NSAppleEventDescriptor(eventClass: 0x6d697363, eventID: 0x646f7363,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: script), forKeyword: AEKeyword(keyDirectObject))
        event.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: 0x4f766572)
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 3)
            if let number = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), number.int32Value != 0 {
                return reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue
                    ?? L10n.string("Adobe After Effects integration failed. Check Automation permission and allow scripts to write files in Adobe After Effects.")
            }
            return nil
        } catch {
            return L10n.string("Adobe After Effects integration failed. Check Automation permission and allow scripts to write files in Adobe After Effects.")
        }
    }
}
