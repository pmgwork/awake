import XCTest
@testable import awake

final class CLITests: XCTestCase {
    func testDurationBoundsAndUnits() throws {
        XCTAssertEqual(try CLIProtocol.duration("30m"), 1800)
        XCTAssertEqual(try CLIProtocol.duration("2h"), 7200)
        XCTAssertEqual(try CLIProtocol.duration("1s"), 1)
        XCTAssertEqual(try CLIProtocol.duration("168h"), 604800)
        for value in ["0s", "-1m", "1.5h", "1", "1d", "169h", "604801s", "nan", "999999999999999999999h", " 1m"] {
            XCTAssertThrowsError(try CLIProtocol.duration(value), value)
        }
    }

    func testStrictCommandParsing() throws {
        XCTAssertEqual(try CLIProtocol.parse(["start"]).command, "start")
        XCTAssertNil(try CLIProtocol.parse(["start"]).durationSeconds)
        XCTAssertNil(try CLIProtocol.parse(["start"]).mode)
        XCTAssertEqual(try CLIProtocol.parse(["start", "--duration", "30m"]).durationSeconds, 1800)
        XCTAssertEqual(try CLIProtocol.parse(["status", "--json"]).command, "status")
        XCTAssertEqual(try CLIProtocol.parse(["stop"]).command, "stop")
        XCTAssertNil(try CLIProtocol.parse(["stop"]).all)
        XCTAssertEqual(try CLIProtocol.parse(["stop", "--all"]).all, true)
        for arguments in [[String](), ["start", "--duration"], ["stop", "--duration", "1m"], ["stop", "--bad"], ["status", "--bad"], ["start", "extra"]] {
            XCTAssertThrowsError(try CLIProtocol.parse(arguments))
        }
    }

    func testModeAutoAndCoolingCommands() throws {
        XCTAssertEqual(try CLIProtocol.parse(["mode", "indefinitely"]).mode, "indefinitely")
        XCTAssertEqual(try CLIProtocol.parse(["mode", "timer", "--duration", "1h"]).durationSeconds, 3600)
        XCTAssertEqual(try CLIProtocol.parse(["mode", "--duration", "1h"]).mode, "timer")
        XCTAssertEqual(try CLIProtocol.parse(["mode", "--duration", "1h"]).durationSeconds, 3600)
        XCTAssertEqual(try CLIProtocol.parse(["mode"]).command, "status")
        XCTAssertEqual(try CLIProtocol.parse(["start", "--mode", "timer"]).mode, "timer")
        XCTAssertEqual(try CLIProtocol.parse(["start", "--duration", "30m", "--mode", "timer"]).durationSeconds, 1800)

        let agentOn = try CLIProtocol.parse(["auto", "agent", "on"])
        XCTAssertEqual(agentOn.command, "auto")
        XCTAssertEqual(agentOn.condition, "agent")
        XCTAssertEqual(agentOn.enabled, true)

        let downloadOff = try CLIProtocol.parse(["auto", "download", "off"])
        XCTAssertEqual(downloadOff.command, "auto")
        XCTAssertEqual(downloadOff.condition, "download")
        XCTAssertEqual(downloadOff.enabled, false)

        XCTAssertEqual(try CLIProtocol.parse(["cooling", "start"]).command, "cooling.start")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "start", "--duration", "10m"]).mode, "timer")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "mode", "indefinitely"]).mode, "indefinitely")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "mode", "--duration", "15m"]).mode, "timer")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "mode"]).command, "cooling.status")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "stop"]).command, "cooling.stop")
        XCTAssertNil(try CLIProtocol.parse(["cooling", "stop"]).all)
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "stop", "--all"]).all, true)
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "status", "--json"]).command, "cooling.status")

        let awakeOn = try CLIProtocol.parse(["cooling", "auto", "awake", "on"])
        XCTAssertEqual(awakeOn.command, "cooling.auto")
        XCTAssertEqual(awakeOn.condition, "awake")
        XCTAssertEqual(awakeOn.enabled, true)

        let renderOff = try CLIProtocol.parse(["cooling", "auto", "render", "off"])
        XCTAssertEqual(renderOff.command, "cooling.auto")
        XCTAssertEqual(renderOff.condition, "render")
        XCTAssertEqual(renderOff.enabled, false)

        let speed = try CLIProtocol.parse(["cooling", "speed", "automatic", "75"])
        XCTAssertEqual(speed.speedTarget, "automatic")
        XCTAssertEqual(speed.speed, 75)
    }

    func testInvalidOptionsAndCoolingDurations() {
        let invalid = [
            ["start", "--mode", "agent"], ["start", "--mode", "download"],
            ["start", "--mode", "indefinitely", "--duration", "30m"],
            ["start", "--mode", "unknown"], ["mode", "unknown"], ["mode", "agent"],
            ["start", "--duration", "1m", "--duration", "2m"],
            ["auto"], ["auto", "agent"], ["auto", "render", "on"], ["auto", "agent", "maybe"],
            ["cooling"], ["cooling", "mode", "download"], ["cooling", "mode", "awake"],
            ["cooling", "mode", "render"], ["cooling", "mode", "agent"],
            ["cooling", "start", "--mode", "awake"], ["cooling", "start", "--mode", "render"],
            ["cooling", "start", "--duration", "1s"],
            ["cooling", "start", "--duration", "2h"],
            ["cooling", "stop", "--bad"], ["cooling", "stop", "--json"],
            ["cooling", "auto"], ["cooling", "auto", "agent", "on"], ["cooling", "auto", "awake", "yes"],
            ["cooling", "speed", "manual", "0"], ["cooling", "speed", "all", "100"],
            ["cooling", "only-on-ac", "on"], ["cooling", "only-on-ac", "off"]
        ]
        for arguments in invalid { XCTAssertThrowsError(try CLIProtocol.parse(arguments), arguments.joined(separator: " ")) }
        XCTAssertThrowsError(try CLIProtocol.validate(CLIRequest(command: "cooling.start", durationSeconds: 1)))
        XCTAssertThrowsError(try CLIProtocol.validate(CLIRequest(command: "cooling.speed", speedTarget: "manual", speed: 200)))
        XCTAssertThrowsError(try CLIProtocol.validate(CLIRequest(command: "cooling.only-on-ac")))
        XCTAssertThrowsError(try CLIProtocol.validate(CLIRequest(command: "auto", condition: "awake", enabled: true)))
        XCTAssertThrowsError(try CLIProtocol.validate(CLIRequest(command: "cooling.auto", condition: "agent", enabled: true)))
        XCTAssertThrowsError(try CLIProtocol.validate(CLIRequest(command: "status", all: true)))
    }

    @MainActor
    func testStatusReportsModesWithCommandNames() {
        XCTAssertEqual(CLIService.modeName(.whileAgentRunning), "indefinitely")
        XCTAssertEqual(CLIService.modeName(.whileDownloading), "indefinitely")
        XCTAssertEqual(CLIService.modeName(.indefinitely), "indefinitely")
        XCTAssertEqual(CLIService.modeName(.timer), "timer")
        for mode in KeepAwakeModeType.allCases {
            XCTAssertTrue(CLIProtocol.modes.contains(CLIService.modeName(mode)))
        }
    }

    @MainActor
    func testIndependentAutoAndManualStopSemantics() throws {
        let coordinator = AwakeCoordinator.shared
        let settings = coordinator.settings
        let savedMode = settings.selectedMode
        let savedDuration = settings.selectedTimerDuration
        let savedAgent = settings.agentMonitoringEnabled
        let savedDownload = settings.downloadMonitoringEnabled
        let savedManual = coordinator.isManualKeepAwakeActive
        let savedAutoCooling = settings.automaticCoolingEnabled
        let savedRenderCooling = settings.renderCoolingEnabled
        defer {
            coordinator.stopManualKeepAwake()
            settings.selectedMode = savedMode
            settings.selectedTimerDuration = savedDuration
            settings.agentMonitoringEnabled = savedAgent
            settings.downloadMonitoringEnabled = savedDownload
            if savedManual { coordinator.startKeepAwake(userInitiated: true) }
            settings.automaticCoolingEnabled = savedAutoCooling
            settings.renderCoolingEnabled = savedRenderCooling
        }

        // auto switches toggle independently without altering the other switch
        XCTAssertTrue(CLIService.shared.handle(try CLIProtocol.parse(["auto", "agent", "on"])).success)
        XCTAssertTrue(CLIService.shared.handle(try CLIProtocol.parse(["auto", "download", "on"])).success)
        XCTAssertTrue(settings.agentMonitoringEnabled)
        XCTAssertTrue(settings.downloadMonitoringEnabled)

        XCTAssertTrue(CLIService.shared.handle(try CLIProtocol.parse(["auto", "agent", "off"])).success)
        XCTAssertFalse(settings.agentMonitoringEnabled)
        XCTAssertTrue(settings.downloadMonitoringEnabled)

        // start uses the selected manual mode and preserves automatic conditions
        XCTAssertTrue(CLIService.shared.handle(try CLIProtocol.parse(["mode", "timer", "--duration", "45m"])).success)
        let started = CLIService.shared.handle(try CLIProtocol.parse(["start"]))
        XCTAssertTrue(started.success)
        XCTAssertEqual(started.mode, "timer")
        XCTAssertEqual(started.manualActive, true)
        XCTAssertEqual(settings.selectedTimerDuration, 2700)
        XCTAssertTrue(settings.downloadMonitoringEnabled)

        // stop ends only manual Keep Awake; stop --all disables automatic switches too
        let stoppedManual = CLIService.shared.handle(try CLIProtocol.parse(["stop"]))
        XCTAssertTrue(stoppedManual.success)
        XCTAssertEqual(stoppedManual.manualActive, false)
        XCTAssertTrue(settings.downloadMonitoringEnabled)

        XCTAssertTrue(CLIService.shared.handle(try CLIProtocol.parse(["auto", "agent", "on"])).success)
        XCTAssertTrue(CLIService.shared.handle(try CLIProtocol.parse(["start"])).success)
        let stoppedAll = CLIService.shared.handle(try CLIProtocol.parse(["stop", "--all"]))
        XCTAssertTrue(stoppedAll.success)
        XCTAssertEqual(stoppedAll.manualActive, false)
        XCTAssertFalse(settings.agentMonitoringEnabled)
        XCTAssertFalse(settings.downloadMonitoringEnabled)

        // cooling auto off and cooling stop work independently without helper
        settings.automaticCoolingEnabled = true
        settings.renderCoolingEnabled = true
        XCTAssertTrue(CLIService.shared.handle(try CLIProtocol.parse(["cooling", "auto", "awake", "off"])).success)
        XCTAssertFalse(settings.automaticCoolingEnabled)
        XCTAssertTrue(settings.renderCoolingEnabled)

        XCTAssertTrue(CLIService.shared.handle(try CLIProtocol.parse(["cooling", "stop"])).success)
        XCTAssertTrue(settings.renderCoolingEnabled)

        XCTAssertTrue(CLIService.shared.handle(try CLIProtocol.parse(["cooling", "stop", "--all"])).success)
        XCTAssertFalse(settings.automaticCoolingEnabled)
        XCTAssertFalse(settings.renderCoolingEnabled)
    }

    @MainActor
    func testMalformedRequestsCannotChangeModeOrDuration() {
        let coordinator = AwakeCoordinator.shared
        let mode = coordinator.settings.selectedMode
        let duration = coordinator.settings.selectedTimerDuration
        let agent = coordinator.settings.agentMonitoringEnabled
        for value in [-1.0, 0, 0.5, 604801, .infinity, .nan] {
            XCTAssertFalse(CLIService.shared.handle(CLIRequest(command: "start", durationSeconds: value)).success)
        }
        let coolingMode = coordinator.settings.coolingMode
        let coolingDuration = coordinator.settings.forcedCoolingDuration
        let speed = coordinator.settings.manualCoolingFanMode
        for request in [
            CLIRequest(command: "unknown"),
            CLIRequest(command: "mode", mode: "invalid"),
            CLIRequest(command: "mode", mode: "agent"),
            CLIRequest(command: "start", durationSeconds: 300, mode: "indefinitely"),
            CLIRequest(command: "auto", condition: "awake", enabled: true),
            CLIRequest(command: "cooling.start", durationSeconds: 60),
            CLIRequest(command: "cooling.mode", mode: "awake"),
            CLIRequest(command: "cooling.auto", condition: "agent", enabled: true),
            CLIRequest(command: "cooling.speed", speedTarget: "manual", speed: 200)
        ] { XCTAssertFalse(CLIService.shared.handle(request).success) }
        XCTAssertEqual(coordinator.settings.coolingMode, coolingMode)
        XCTAssertEqual(coordinator.settings.forcedCoolingDuration, coolingDuration)
        XCTAssertEqual(coordinator.settings.manualCoolingFanMode, speed)
        XCTAssertEqual(coordinator.settings.selectedMode, mode)
        XCTAssertEqual(coordinator.settings.selectedTimerDuration, duration)
        XCTAssertEqual(coordinator.settings.agentMonitoringEnabled, agent)
    }
}
