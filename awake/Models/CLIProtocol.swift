import Foundation

/// Shared wire format for the bundled command and the running menu bar app.
nonisolated enum CLIProtocol {
    static var portName: String { "pmgwork.awake.cli.v1.\(getuid())" }
    static let modes = ["indefinitely", "timer", "agent", "download"]
    static let coolingModes = ["indefinitely", "timer", "agent"]
    static let coolingDurations: [TimeInterval] = [300, 600, 900, 1800]
    static let invalidArguments = "Invalid arguments. See 'awake --help'."
    static let usage = """
    Usage: awake start [--mode <mode>] [--duration <duration>]
           awake stop
           awake mode [<mode>] [--duration <duration>]
           awake status [--json]
           awake cooling start [--mode <mode>] [--duration <duration>]
           awake cooling stop
           awake cooling mode [<mode>] [--duration <duration>]
           awake cooling speed <automatic|manual> <50|75|100>
           awake cooling status [--json]
           awake --help

    Keep Awake modes: indefinitely, timer, agent, download.
    Cooling modes: indefinitely, timer, agent.
    --duration implies timer mode. start without options keeps its original
    behavior (indefinitely); cooling start uses the selected cooling mode.
    mode selects without starting manual modes; conditional modes follow the app.
    Keep Awake durations: positive whole numbers with s, m, h; maximum 7 days.
    Cooling durations: 5m, 10m, 15m, 30m (same presets as the app).
    Starting again resets the timer. Requires Awake.app; it launches if needed.
    """

    static func duration(_ value: String) throws -> TimeInterval {
        guard let unit = value.last,
              let multiplier: Int = ["s": 1, "m": 60, "h": 3600][String(unit)],
              !value.dropLast().isEmpty,
              value.dropLast().allSatisfy({ $0.isASCII && $0.isNumber }),
              let count = Int(value.dropLast()), count > 0,
              count <= 604800 / multiplier else {
            throw CLIError(message: "Invalid duration '\(value)'. Use 1s–168h, for example 30m.")
        }
        return TimeInterval(count * multiplier)
    }

    static func parse(_ arguments: [String]) throws -> CLIRequest {
        var args = arguments
        let cooling = args.first == "cooling"
        if cooling { args.removeFirst() }
        guard let action = args.first else { throw CLIError(message: invalidArguments) }
        args.removeFirst()
        let command = (cooling ? "cooling." : "") + action
        var request = CLIRequest(command: command)
        switch action {
        case "status":
            guard args.isEmpty || args == ["--json"] else { throw CLIError(message: invalidArguments) }
        case "stop":
            guard args.isEmpty else { throw CLIError(message: invalidArguments) }
        case "start", "mode":
            if action == "mode" {
                if args.isEmpty { return CLIRequest(command: cooling ? "cooling.status" : "status") }
                request.mode = args.removeFirst()
            }
            while !args.isEmpty {
                let option = args.removeFirst()
                guard option == "--duration" || (option == "--mode" && action == "start") else {
                    throw CLIError(message: "Unknown option '\(option)'. See 'awake --help'.")
                }
                guard !args.isEmpty, !args[0].hasPrefix("--") else {
                    let values = option == "--mode"
                        ? (cooling ? coolingModes : modes).joined(separator: ", ")
                        : (cooling ? "5m, 10m, 15m, 30m" : "for example 30m or 2h")
                    throw CLIError(message: "\(option) requires a value: \(values).")
                }
                let value = args.removeFirst()
                switch option {
                case "--mode" where action == "start" && request.mode == nil: request.mode = value
                case "--duration" where request.durationSeconds == nil: request.durationSeconds = try duration(value)
                default: throw CLIError(message: invalidArguments)
                }
            }
            if request.durationSeconds != nil && request.mode == nil { request.mode = "timer" }
        case "speed" where cooling:
            guard args.count == 2, let speed = Int(args[1]) else { throw CLIError(message: invalidArguments) }
            request.speedTarget = args[0]
            request.speed = speed
        default: throw CLIError(message: invalidArguments)
        }
        try validate(request)
        return request
    }

    /// Validate again in the app so malformed wire requests cannot change settings.
    static func validate(_ request: CLIRequest) throws {
        let cooling = request.command.hasPrefix("cooling.")
        let action = cooling ? String(request.command.dropFirst(8)) : request.command
        if let duration = request.durationSeconds {
            guard duration.isFinite, duration >= 1, duration <= 604800, duration.rounded() == duration else {
                throw CLIError(message: "Duration must be whole seconds between 1 and 604800.")
            }
            guard !cooling || coolingDurations.contains(duration) else {
                throw CLIError(message: "Cooling duration must be 5m, 10m, 15m, or 30m.")
            }
        }
        if let mode = request.mode, !(cooling ? coolingModes : modes).contains(mode) {
            throw CLIError(message: "Invalid mode '\(mode)'. Choose: \((cooling ? coolingModes : modes).joined(separator: ", ")).")
        }
        if request.durationSeconds != nil, let mode = request.mode, mode != "timer" {
            throw CLIError(message: "--duration requires timer mode.")
        }
        switch action {
        case "start", "mode":
            guard request.speed == nil, request.speedTarget == nil,
                  action != "mode" || request.mode != nil,
                  request.mode == nil || (cooling ? coolingModes : modes).contains(request.mode!),
                  request.durationSeconds == nil || request.mode == nil || request.mode == "timer" else {
                throw CLIError(message: "Invalid mode or options. See 'awake --help'.")
            }
        case "stop", "status":
            guard request.mode == nil, request.durationSeconds == nil, request.speed == nil,
                  request.speedTarget == nil else { throw CLIError(message: invalidArguments) }
        case "speed" where cooling:
            guard request.mode == nil, request.durationSeconds == nil,
                  ["automatic", "manual"].contains(request.speedTarget ?? ""),
                  [50, 75, 100].contains(request.speed ?? 0) else { throw CLIError(message: invalidArguments) }
        default: throw CLIError(message: "Unknown command. See 'awake --help'.")
        }
    }
}

nonisolated struct CLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

nonisolated struct CLIRequest: Codable {
    let command: String
    var durationSeconds: TimeInterval? = nil
    var mode: String? = nil
    var speedTarget: String? = nil
    var speed: Int? = nil
}

nonisolated struct CLIResponse: Codable {
    let success: Bool
    let error: String?
    let active: Bool
    let mode: String
    let remainingSeconds: Int
    let timerEndsAt: Date?
    let sleepPreventionHealth: String
    var cooling: CLICoolingStatus? = nil
    var waitingForActivity: Bool? = nil
}

nonisolated struct CLICoolingStatus: Codable {
    let mode: String
    let armed: Bool
    let active: Bool
    let available: Bool
    let helperInstalled: Bool
    let blockedByLowBattery: Bool
    let durationSeconds: Int
    let remainingSeconds: Int
    let timerEndsAt: Date?
    let automaticSpeed: Int
    let manualSpeed: Int
    let onlyOnAC: Bool
    let fanControl: String
    let error: String?
}
