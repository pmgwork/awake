//
//  BlenderRenderIntegration.swift
//  Awake
//

import Foundation
import Darwin

/// Blender gives no outside signal for renders started from its window, so
/// Awake installs a startup script into each Blender version's user scripts
/// folder. Blender imports it at launch; it creates a file named after
/// Blender's process ID while a render job runs and removes it afterward.
nonisolated enum BlenderRenderIntegration {
    static let scriptName = "awake_render_monitor.py"
    static let ownerMarker = "# Installed by Awake (pmgwork.awake)."

    static var blenderSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Blender", isDirectory: true)
    }

    static var signalDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Awake/render-sessions", isDirectory: true)
    }

    static func script(signalDirectory: URL) -> String {
        """
        \(ownerMarker)
        # Tells Awake when a render runs so it can cool the Mac.
        # Use Unlink in Awake to remove this file.
        import os

        import bpy
        from bpy.app.handlers import persistent

        _DIRECTORY = \(pythonString(signalDirectory.path))
        _PATH = os.path.join(_DIRECTORY, "blender-%d" % os.getpid())


        @persistent
        def _awake_render_started(*_args):
            try:
                os.makedirs(_DIRECTORY, mode=0o700, exist_ok=True)
                open(_PATH, "w").close()
            except OSError:
                pass


        @persistent
        def _awake_render_ended(*_args):
            try:
                os.remove(_PATH)
            except OSError:
                pass


        _HANDLERS = (
            (bpy.app.handlers.render_init, _awake_render_started),
            (bpy.app.handlers.render_complete, _awake_render_ended),
            (bpy.app.handlers.render_cancel, _awake_render_ended),
        )


        def register():
            for handlers, function in _HANDLERS:
                for existing in [h for h in handlers if getattr(h, "__name__", "") == function.__name__]:
                    handlers.remove(existing)
                handlers.append(function)


        def unregister():
            for handlers, function in _HANDLERS:
                for existing in [h for h in handlers if getattr(h, "__name__", "") == function.__name__]:
                    handlers.remove(existing)
            _awake_render_ended()

        """
    }

    enum Status { case unlinked, linked, needsRepair }

    enum IntegrationError: LocalizedError {
        case noVersions, conflictingFile(String)
        var errorDescription: String? {
            switch self {
            case .noVersions:
                return L10n.string("Open Blender once before linking it, then try again.")
            case .conflictingFile(let path):
                return L10n.format("Awake cannot replace a file it did not create: %@", path)
            }
        }
    }

    static func status(blenderDirectory: URL = blenderSupportDirectory,
                       signalDirectory: URL = signalDirectory,
                       fileManager: FileManager = .default) -> Status {
        let files = scriptFiles(in: blenderDirectory, fileManager: fileManager)
        let contents = files.map { try? Data(contentsOf: $0) }
        guard contents.contains(where: { $0.map(isOwned) == true }) else { return .unlinked }
        return contents.allSatisfy { $0.map(isOwned) == true } ? .linked : .needsRepair
    }

    /// Explicit linking only; monitoring never adds or removes scripts.
    static func install(blenderDirectory: URL = blenderSupportDirectory,
                        signalDirectory: URL = signalDirectory,
                        fileManager: FileManager = .default) throws {
        let files = scriptFiles(in: blenderDirectory, fileManager: fileManager)
        guard !files.isEmpty else { throw IntegrationError.noVersions }
        // Check every destination before changing any version.
        for file in files where fileManager.fileExists(atPath: file.path) {
            guard isOwned(try Data(contentsOf: file)) else {
                throw IntegrationError.conflictingFile(file.path)
            }
        }
        let contents = Data(script(signalDirectory: signalDirectory).utf8)
        for file in files {
            if (try? Data(contentsOf: file)) == contents { continue }
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, options: .atomic)
        }
    }

    /// Removes only scripts that Awake wrote, keeping unrelated files.
    static func uninstall(blenderDirectory: URL = blenderSupportDirectory,
                          fileManager: FileManager = .default) throws {
        for file in scriptFiles(in: blenderDirectory, fileManager: fileManager) {
            guard let existing = try? Data(contentsOf: file), isOwned(existing) else { continue }
            try fileManager.removeItem(at: file)
        }
    }

    private static func scriptFiles(in directory: URL, fileManager: FileManager) -> [URL] {
        versionDirectories(in: directory, fileManager: fileManager).map {
            $0.appendingPathComponent("scripts/startup/\(scriptName)")
        }
    }

    /// Whether a running Blender reports a render. Files left by a Blender
    /// that quit or crashed during a render are removed.
    static func hasActiveRender(signalDirectory: URL = signalDirectory,
                                fileManager: FileManager = .default,
                                isBlender: (pid_t) -> Bool) -> Bool {
        guard let names = try? fileManager.contentsOfDirectory(atPath: signalDirectory.path) else { return false }
        var active = false
        for name in names where name.hasPrefix("blender-") {
            if let pid = pid_t(name.dropFirst("blender-".count)), isRunning(pid), isBlender(pid) {
                active = true
            } else {
                try? fileManager.removeItem(at: signalDirectory.appendingPathComponent(name))
            }
        }
        return active
    }

    /// Version folders such as "4.2" or "5.2".
    static func versionDirectories(in blenderDirectory: URL, fileManager: FileManager) -> [URL] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: blenderDirectory.path) else { return [] }
        return names.filter { name in
            let parts = name.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        }
        .sorted()
        .map { blenderDirectory.appendingPathComponent($0, isDirectory: true) }
    }

    private static func isOwned(_ data: Data) -> Bool {
        String(decoding: data.prefix(256), as: UTF8.self).hasPrefix(ownerMarker)
    }

    private static func isRunning(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    private static func pythonString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
