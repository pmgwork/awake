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
        XCTAssertEqual(try CLIProtocol.parse(["start", "--duration", "30m"]).durationSeconds, 1800)
        XCTAssertEqual(try CLIProtocol.parse(["status", "--json"]).command, "status")
        XCTAssertEqual(try CLIProtocol.parse(["stop"]).command, "stop")
        for arguments in [[String](), ["start", "--duration"], ["stop", "--duration", "1m"], ["status", "--bad"], ["start", "extra"]] {
            XCTAssertThrowsError(try CLIProtocol.parse(arguments))
        }
    }

    func testModeAndCoolingCommands() throws {
        XCTAssertEqual(try CLIProtocol.parse(["mode", "agent"]).mode, "agent")
        XCTAssertEqual(try CLIProtocol.parse(["mode"]).command, "status")
        XCTAssertEqual(try CLIProtocol.parse(["start", "--mode", "download"]).mode, "download")
        XCTAssertEqual(try CLIProtocol.parse(["start", "--duration", "30m", "--mode", "timer"]).durationSeconds, 1800)
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "start"]).command, "cooling.start")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "start", "--duration", "10m"]).mode, "timer")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "mode", "agent"]).mode, "agent")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "mode"]).command, "cooling.status")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "stop"]).command, "cooling.stop")
        XCTAssertEqual(try CLIProtocol.parse(["cooling", "status", "--json"]).command, "cooling.status")
        let speed = try CLIProtocol.parse(["cooling", "speed", "automatic", "75"])
        XCTAssertEqual(speed.speedTarget, "automatic")
        XCTAssertEqual(speed.speed, 75)
    }

    func testInvalidOptionsAndCoolingDurations() {
        let invalid = [
            ["start", "--mode", "agent", "--duration", "30m"],
            ["start", "--mode", "unknown"], ["mode", "unknown"],
            ["start", "--duration", "1m", "--duration", "2m"],
            ["cooling"], ["cooling", "mode", "download"],
            ["cooling", "start", "--duration", "1s"],
            ["cooling", "start", "--duration", "2h"],
            ["cooling", "speed", "manual", "0"], ["cooling", "speed", "all", "100"],
            ["cooling", "only-on-ac", "on"], ["cooling", "only-on-ac", "off"], ["cooling", "stop", "--json"]
        ]
        for arguments in invalid { XCTAssertThrowsError(try CLIProtocol.parse(arguments), arguments.joined(separator: " ")) }
        XCTAssertThrowsError(try CLIProtocol.validate(CLIRequest(command: "cooling.start", durationSeconds: 1)))
        XCTAssertThrowsError(try CLIProtocol.validate(CLIRequest(command: "cooling.speed", speedTarget: "manual", speed: 200)))
        XCTAssertThrowsError(try CLIProtocol.validate(CLIRequest(command: "cooling.only-on-ac")))
    }

    @MainActor
    func testMalformedRequestsCannotChangeModeOrDuration() {
        let coordinator = AwakeCoordinator.shared
        let mode = coordinator.settings.selectedMode
        let duration = coordinator.settings.selectedTimerDuration
        for value in [-1.0, 0, 0.5, 604801, .infinity, .nan] {
            XCTAssertFalse(CLIService.shared.handle(CLIRequest(command: "start", durationSeconds: value)).success)
        }
        let coolingMode = coordinator.settings.coolingMode
        let coolingDuration = coordinator.settings.forcedCoolingDuration
        let speed = coordinator.settings.manualCoolingFanMode
        for request in [
            CLIRequest(command: "unknown"),
            CLIRequest(command: "mode", mode: "invalid"),
            CLIRequest(command: "start", durationSeconds: 300, mode: "agent"),
            CLIRequest(command: "cooling.start", durationSeconds: 60),
            CLIRequest(command: "cooling.mode", mode: "download"),
            CLIRequest(command: "cooling.speed", speedTarget: "manual", speed: 200)
        ] { XCTAssertFalse(CLIService.shared.handle(request).success) }
        XCTAssertEqual(coordinator.settings.coolingMode, coolingMode)
        XCTAssertEqual(coordinator.settings.forcedCoolingDuration, coolingDuration)
        XCTAssertEqual(coordinator.settings.manualCoolingFanMode, speed)
        XCTAssertEqual(coordinator.settings.selectedMode, mode)
        XCTAssertEqual(coordinator.settings.selectedTimerDuration, duration)
    }
}
