import AppKit
import CoreFoundation

func send(_ request: CLIRequest, to port: CFMessagePort) throws -> CLIResponse {
    let data = try JSONEncoder().encode(request)
    var reply: Unmanaged<CFData>?
    let result = CFMessagePortSendRequest(port, 1, data as CFData, 5, 5, CFRunLoopMode.defaultMode.rawValue, &reply)
    guard result == kCFMessagePortSuccess, let reply else {
        throw CLIError(message: "Awake did not respond (\(result)). The command may have been applied; check awake status before retrying.")
    }
    return try JSONDecoder().decode(CLIResponse.self, from: reply.takeRetainedValue() as Data)
}

@MainActor
func connect() throws -> CFMessagePort {
    if let port = CFMessagePortCreateRemote(nil, CLIProtocol.portName as CFString) { return port }
    // Resolve symlinks so ~/.local/bin/awake still launches its containing app.
    let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    let bundledApp = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard bundledApp.pathExtension == "app", FileManager.default.fileExists(atPath: bundledApp.path) else {
        throw CLIError(message: "Run the CLI bundled in Awake.app/Contents/Helpers/awake, or symlink it into your PATH.")
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    var launchError: Error?
    var finished = false
    NSWorkspace.shared.openApplication(at: bundledApp, configuration: configuration) { _, error in
        launchError = error
        finished = true
    }
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
        if let port = CFMessagePortCreateRemote(nil, CLIProtocol.portName as CFString) { return port }
        if finished, let launchError { throw launchError }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    throw CLIError(message: "Timed out waiting for Awake. Quit older Awake versions and launch this app, then try again.")
}

if CommandLine.arguments.count == 1 || ["--help", "-h"].contains(CommandLine.arguments[1]) {
    print(CLIProtocol.usage)
    exit(0)
}
do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let request = try CLIProtocol.parse(arguments)
    let response = try send(request, to: MainActor.assumeIsolated { try connect() })
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(response), as: UTF8.self))
    } else {
        guard response.success else { throw CLIError(message: response.error ?? "Command failed.") }
        if !["status", "cooling.status"].contains(request.command) {
            switch request.command {
            case "start":
                print("Keep Awake: \(response.active ? "active" : response.waitingForActivity == true ? "waiting" : "stopped") (\(response.mode)).")
            case "stop": print("Keep Awake stopped.")
            case "mode": print("Keep Awake mode: \(request.mode ?? response.mode).")
            case "cooling.start":
                if let cooling = response.cooling {
                    print("Cooling: \(cooling.active ? "active" : cooling.armed ? "waiting" : "stopped") (\(cooling.mode)).")
                } else { print("Cooling started.") }
            case "cooling.stop": print("Cooling stopped.")
            case "cooling.mode": print("Cooling mode: \(request.mode ?? "").")
            case "cooling.speed": print("\((request.speedTarget ?? "").capitalized) cooling speed: \(request.speed ?? 0)%.")
            default: break
            }
            exit(0)
        }
        print("Keep Awake: \(response.active ? "active" : response.waitingForActivity == true ? "waiting" : "stopped")")
        print("Mode: \(response.mode)")
        if response.timerEndsAt != nil { print("Remaining: \(response.remainingSeconds)s") }
        print("Sleep prevention: \(response.sleepPreventionHealth)")
        if let cooling = response.cooling {
            print("Cooling: \(cooling.active ? "active" : cooling.armed ? "waiting" : "stopped")")
            print("Cooling mode: \(cooling.mode)")
            if cooling.timerEndsAt != nil { print("Cooling remaining: \(cooling.remainingSeconds)s") }
            print("Cooling available: \(cooling.available ? "yes" : "no") (helper: \(cooling.helperInstalled ? "installed" : "missing"), low-battery block: \(cooling.blockedByLowBattery ? "yes" : "no"))")
            print("Cooling speed: automatic \(cooling.automaticSpeed)%, manual \(cooling.manualSpeed)%")
            print("Only on AC: \(cooling.onlyOnAC ? "on" : "off")")
            print("Fan control: \(cooling.fanControl)")
            if let error = cooling.error { print("Fan error: \(error)") }
        }
    }
    exit(response.success ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("awake: \(error.localizedDescription)\n".utf8))
    exit(1)
}
