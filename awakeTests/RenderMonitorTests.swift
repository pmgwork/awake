import XCTest
@testable import awake

final class RenderMonitorTests: XCTestCase {
    func testSignalStartsAtOnceAndBridgesShortGaps() {
        var detector = RenderActivityDetector()
        let start = Date()
        func at(_ seconds: TimeInterval, _ signaled: Bool) -> Bool {
            detector.update(signaled: signaled, now: start.addingTimeInterval(seconds))
        }
        XCTAssertFalse(at(-1, false))
        XCTAssertTrue(at(0, true))
        XCTAssertTrue(at(6, false))
        XCTAssertTrue(at(9, true))
        XCTAssertTrue(at(18, false))
        XCTAssertFalse(at(19, false))
    }

    func testDetectsExportProcessesAndIgnoresAppWindows() {
        func kind(_ path: String, _ arguments: [String] = []) -> RenderApp? {
            RenderProcessSampler.match(executablePath: path, arguments: { arguments })
        }
        let ame = "/Applications/Adobe Media Encoder 2027/Adobe Media Encoder 2027.app/Contents/MacOS/Adobe Media Encoder 2027"
        XCTAssertTrue(AMELoadSampler.isMediaEncoder(executablePath: ame))
        XCTAssertFalse(AMELoadSampler.isMediaEncoder(executablePath: "/tmp/Adobe Media Encoder"))
        XCTAssertNil(kind(ame)) // An open AME is not an explicit export signal.
        let blender = "/Applications/Blender.app/Contents/MacOS/Blender"
        XCTAssertNil(kind(blender, [blender]))
        XCTAssertNil(kind(blender, [blender, "-b", "scene.blend", "--python", "export.py"]))
        XCTAssertEqual(kind(blender, [blender, "-b", "scene.blend", "-f", "1"]), .blender)
        XCTAssertEqual(kind(blender, [blender, "--background", "scene.blend", "--render-anim"]), .blender)

        XCTAssertEqual(kind("/Applications/Adobe After Effects 2027/aerender"), .afterEffects)
        XCTAssertEqual(kind("/Applications/Houdini/Current/Frameworks/Houdini.framework/Versions/Current/Resources/bin/husk"), .houdini)
        XCTAssertEqual(kind("/Applications/Houdini/bin/mantra"), .houdini)

        XCTAssertNil(kind("/Applications/Adobe After Effects 2027/Adobe After Effects 2027.app/Contents/MacOS/After Effects"))
        XCTAssertNil(kind("/Applications/Houdini/Current/Frameworks/Houdini.framework/Versions/Current/Resources/bin/hython3.13"))
        XCTAssertNil(kind("/Applications/Adobe After Effects 2027/Contents/MacOS/After Effects Render Engine"))
        XCTAssertNil(kind("/Applications/Houdini/bin/hbatch"))
        // An open app or scripting shell alone is not an export.
        XCTAssertNil(kind("/Applications/Houdini/Current/Houdini FX 22.0.429.app/Contents/MacOS/houdini"))
    }

    func testAMELoadUsesEitherProcessorAndWaitsForSustainedQuiet() {
        var detector = AMELoadDetector()
        XCTAssertFalse(detector.update(cpu: 2, gpu: 0, now: 0))
        XCTAssertFalse(detector.update(cpu: 0, gpu: 0, now: 6))
        XCTAssertFalse(detector.update(cpu: 0, gpu: 0.5, now: 9))
        XCTAssertTrue(detector.update(cpu: 0, gpu: 0.5, now: 19))
        // Either source keeps cooling on; the gap between thresholds avoids flapping.
        XCTAssertTrue(detector.update(cpu: 2, gpu: 0, now: 25))
        XCTAssertTrue(detector.update(cpu: 0.7, gpu: 0.15, now: 30))
        XCTAssertTrue(detector.update(cpu: 0, gpu: 0, now: 40))
        XCTAssertTrue(detector.update(cpu: 0, gpu: 0, now: 69))
        XCTAssertFalse(detector.update(cpu: 0, gpu: 0, now: 70))
        // CPU-only operation still works when the driver exposes no GPU counter.
        XCTAssertFalse(detector.update(cpu: 2, gpu: 0, now: 80))
        XCTAssertTrue(detector.update(cpu: 2, gpu: 0, now: 90))
    }

    func testAMELoadDeltasIgnoreNewProcessesClientsAndResets() {
        let previous = AMELoadSampler.Sample(uptime: 10, isRunning: true,
            cpu: [1: .init(start: 100, seconds: 10), 2: .init(start: 200, seconds: 90)],
            gpu: [10: .init(pid: 1, nanoseconds: [1_000_000_000])])
        let current = AMELoadSampler.Sample(uptime: 12, isRunning: true,
            cpu: [1: .init(start: 100, seconds: 12), 2: .init(start: 999, seconds: 200), 3: .init(start: 300, seconds: 500)],
            gpu: [10: .init(pid: 1, nanoseconds: [2_000_000_000]), 20: .init(pid: 3, nanoseconds: [9_000_000_000])])
        let load = current.load(since: previous)!
        XCTAssertEqual(load.cpu, 1, accuracy: 0.001)
        XCTAssertEqual(load.gpu, 0.5, accuracy: 0.001)
        let reset = AMELoadSampler.Sample(uptime: 14, isRunning: true,
            cpu: [1: .init(start: 100, seconds: 1)], gpu: [10: .init(pid: 1, nanoseconds: [0])])
        XCTAssertEqual(reset.load(since: current)!.cpu, 0)
        XCTAssertEqual(reset.load(since: current)!.gpu, 0)
        XCTAssertNil(current.load(since: current))
        let afterSleep = AMELoadSampler.Sample(uptime: 100, isRunning: true, cpu: current.cpu, gpu: current.gpu)
        XCTAssertNil(afterSleep.load(since: current))
    }

    func testBlenderScriptInstallsIntoVersionFoldersAndKeepsOtherFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let signals = root.appendingPathComponent("signals")
        for name in ["4.2", "5.2", "config"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let foreignStartup = root.appendingPathComponent("5.2/scripts/startup")
        try FileManager.default.createDirectory(at: foreignStartup, withIntermediateDirectories: true)
        let foreign = foreignStartup.appendingPathComponent(BlenderRenderIntegration.scriptName)
        try Data("print('mine')\n".utf8).write(to: foreign)

        XCTAssertEqual(BlenderRenderIntegration.status(blenderDirectory: root), .unlinked)
        XCTAssertThrowsError(try BlenderRenderIntegration.install(blenderDirectory: root, signalDirectory: signals))
        XCTAssertEqual(try String(contentsOf: foreign, encoding: .utf8), "print('mine')\n")
        try FileManager.default.removeItem(at: foreign)
        try BlenderRenderIntegration.install(blenderDirectory: root, signalDirectory: signals)
        XCTAssertEqual(BlenderRenderIntegration.status(blenderDirectory: root), .linked)
        let installed = root.appendingPathComponent("4.2/scripts/startup/\(BlenderRenderIntegration.scriptName)")
        XCTAssertTrue(try String(contentsOf: installed, encoding: .utf8).contains(signals.path))
        // A missing script in another version must offer repair.
        try Data("print('mine')\n".utf8).write(to: foreign)
        XCTAssertEqual(BlenderRenderIntegration.status(blenderDirectory: root), .needsRepair)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("config/scripts").path))

        try BlenderRenderIntegration.uninstall(blenderDirectory: root)
        XCTAssertEqual(BlenderRenderIntegration.status(blenderDirectory: root), .unlinked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
    }

    func testBlenderLinkWithoutVersionFoldersFails() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try BlenderRenderIntegration.install(blenderDirectory: missing))
        XCTAssertEqual(BlenderRenderIntegration.status(blenderDirectory: missing), .unlinked)
    }

    func testSignalFilesCountOnlyForRunningBlender() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let running = directory.appendingPathComponent("blender-\(getpid())")
        let stale = directory.appendingPathComponent("blender-999999")
        for file in [running, stale] { FileManager.default.createFile(atPath: file.path, contents: nil) }

        XCTAssertTrue(BlenderRenderIntegration.hasActiveRender(signalDirectory: directory, isBlender: { _ in true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        // A reused process ID that is no longer Blender does not count.
        XCTAssertFalse(BlenderRenderIntegration.hasActiveRender(signalDirectory: directory, isBlender: { _ in false }))
    }

    func testAEReportRejectsPreviousSessionAndIncompleteWrites() {
        let active = Data(#"{"token":"current","active":true}"#.utf8)
        XCTAssertTrue(AfterEffectsRenderIntegration.isActiveReport(active, token: "current"))
        XCTAssertFalse(AfterEffectsRenderIntegration.isActiveReport(active, token: "previous"))
        XCTAssertFalse(AfterEffectsRenderIntegration.isActiveReport(Data(#"{"token":"current","active":false}"#.utf8), token: "current"))
        XCTAssertFalse(AfterEffectsRenderIntegration.isActiveReport(Data(#"{"token":"current","active":"#.utf8), token: "current"))
    }

    func testRenderCoolingIgnoresLidButStopsAtLowBattery() {
        let rendering = CoolingActivity(manualArmed: false, manualMode: .forced, automaticEnabled: false,
            automaticRequested: false, renderingRequested: true, batteryBlocked: false, helperAvailable: true)
        XCTAssertTrue(rendering.rendering)
        XCTAssertEqual(rendering.effectiveMode, .whileKeepAwakeIsOn)
        for (battery, helper) in [(true, true), (false, false)] {
            let blocked = CoolingActivity(manualArmed: false, manualMode: .forced, automaticEnabled: false,
                automaticRequested: false, renderingRequested: true, batteryBlocked: battery, helperAvailable: helper)
            XCTAssertFalse(blocked.active)
        }
    }
}
