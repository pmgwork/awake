import Foundation
import CoreFoundation

/// CFMessagePort uses the current login session; the name also scopes it to the user.
@MainActor
final class CLIService {
    static let shared = CLIService()
    private var port: CFMessagePort?
    private var source: CFRunLoopSource?

    func start() {
        guard port == nil else { return }
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        port = CFMessagePortCreateLocal(nil, CLIProtocol.portName as CFString, { _, _, data, _ in
            guard let data else { return nil }
            // This port is attached exclusively to the main run loop.
            return MainActor.assumeIsolated {
                let response: CLIResponse
                do {
                    let request = try JSONDecoder().decode(CLIRequest.self, from: data as Data)
                    response = CLIService.shared.handle(request)
                } catch {
                    response = CLIService.shared.snapshot(error: error.localizedDescription)
                }
                guard let encoded = try? JSONEncoder().encode(response) else { return nil }
                return Unmanaged.passRetained(encoded as CFData)
            }
        }, &context, nil)
        guard let port else {
            NSLog("[CLI] Could not register command port; another Awake instance may be running.")
            return
        }
        source = CFMessagePortCreateRunLoopSource(nil, port, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    func handle(_ request: CLIRequest) -> CLIResponse {
        do { try CLIProtocol.validate(request) }
        catch { return snapshot(error: error.localizedDescription) }
        let coordinator = AwakeCoordinator.shared
        let settings = coordinator.settings
        if coordinator.isRemovingHardwareAuthorization,
           !["status", "cooling.status", "stop", "cooling.stop"].contains(request.command) {
            return snapshot(error: "Hardware authorization is being removed. Try again when it finishes.")
        }
        switch request.command {
        case "start", "mode":
            let mode: KeepAwakeModeType
            if let requestedMode = request.mode {
                mode = keepAwakeMode(requestedMode)
            } else if request.durationSeconds != nil {
                mode = .timer
            } else {
                mode = settings.selectedMode == .timer ? .timer : .indefinitely
            }
            coordinator.selectMode(mode)
            if let duration = request.durationSeconds { coordinator.setTimerDuration(duration) }
            if request.command == "start" {
                coordinator.startKeepAwake(userInitiated: true)
                if !coordinator.isManualKeepAwakeActive {
                    return snapshot(error: "Keep Awake could not be started.")
                }
            }
        case "stop":
            if request.all == true {
                coordinator.stopKeepAwake()
            } else {
                coordinator.stopManualKeepAwake()
            }
        case "auto":
            let enabled = request.enabled == true
            switch request.condition {
            case "agent":
                coordinator.setAgentMonitoringEnabled(enabled)
            case "download":
                coordinator.setDownloadMonitoringEnabled(enabled)
            default:
                return snapshot(error: CLIProtocol.invalidArguments)
            }
        case "cooling.start", "cooling.mode":
            // Keep a failed start from replacing a running cooling session or its settings.
            coordinator.evaluateState()
            let mode: CoolingMode
            if let requestedMode = request.mode {
                mode = coolingMode(requestedMode)
            } else if request.durationSeconds != nil {
                mode = .timed
            } else {
                mode = settings.coolingMode == .timed ? .timed : .forced
            }
            if request.command == "cooling.start" && !coordinator.canStartCooling(mode) {
                return snapshot(error: coolingUnavailableReason())
            }
            coordinator.selectCoolingMode(mode)
            if let duration = request.durationSeconds { coordinator.setCoolingDuration(duration) }
            if request.command == "cooling.start" {
                coordinator.startCooling()
                guard settings.coolingArmed else { return snapshot(error: coolingUnavailableReason()) }
            }
        case "cooling.stop":
            if request.all == true {
                coordinator.stopCooling()
            } else {
                coordinator.stopManualCooling()
            }
        case "cooling.auto":
            coordinator.evaluateState()
            let enabled = request.enabled == true
            switch request.condition {
            case "awake":
                if enabled && !coordinator.canStartCooling(.whileKeepAwakeIsOn) {
                    return snapshot(error: coolingUnavailableReason())
                }
                coordinator.setAutomaticCoolingEnabled(enabled)
                if enabled && !settings.automaticCoolingEnabled {
                    return snapshot(error: coolingUnavailableReason())
                }
            case "render":
                if enabled && !coordinator.canStartCooling(.whileKeepAwakeIsOn) {
                    return snapshot(error: coolingUnavailableReason())
                }
                coordinator.setRenderCoolingEnabled(enabled)
                if enabled && !settings.renderCoolingEnabled {
                    return snapshot(error: coolingUnavailableReason())
                }
            default:
                return snapshot(error: CLIProtocol.invalidArguments)
            }
        case "cooling.speed":
            coordinator.evaluateState()
            guard coordinator.isFanHelperInstalled else {
                return snapshot(error: "Cooling requires the helper. Install it in Settings → Permissions.")
            }
            let speed: FanMode = request.speed == 50 ? .moderate : request.speed == 75 ? .aggressive : .maximum
            if request.speedTarget == "automatic" { settings.automaticCoolingFanMode = speed }
            else { settings.manualCoolingFanMode = speed }
            coordinator.evaluateState()
        case "status", "cooling.status": break
        default: return snapshot(error: "Unknown command.")
        }
        return snapshot()
    }

    private func keepAwakeMode(_ name: String) -> KeepAwakeModeType {
        name == "timer" ? .timer : .indefinitely
    }

    /// Reports modes with the names the command accepts.
    static func modeName(_ mode: KeepAwakeModeType) -> String {
        mode == .timer ? "timer" : "indefinitely"
    }

    private func coolingMode(_ name: String) -> CoolingMode {
        name == "timer" ? .timed : .forced
    }

    private func coolingUnavailableReason() -> String {
        let coordinator = AwakeCoordinator.shared
        if !coordinator.isFanHelperInstalled {
            return "Cooling requires the helper. Install it in Settings → Permissions, then try again."
        }
        return "Cooling could not start. Check the low-battery cutoff and Settings → Permissions."
    }

    private func speedPercent(_ mode: FanMode) -> Int {
        switch mode {
        case .moderate: return 50
        case .aggressive: return 75
        case .maximum: return 100
        case .auto: return 0
        }
    }

    private func snapshot(error: String? = nil) -> CLIResponse {
        let coordinator = AwakeCoordinator.shared
        let settings = coordinator.settings
        let remaining = coordinator.timerEndDate.map { max(0, Int(ceil($0.timeIntervalSinceNow))) } ?? 0
        let coolingMode = settings.coolingMode == .timed ? "timer" : "indefinitely"
        return CLIResponse(
            success: error == nil, error: error, active: coordinator.isActive,
            mode: Self.modeName(settings.selectedMode),
            remainingSeconds: remaining, timerEndsAt: coordinator.timerEndDate,
            sleepPreventionHealth: coordinator.sleepManager.health.rawValue,
            cooling: CLICoolingStatus(
                mode: coolingMode, armed: settings.coolingArmed || settings.automaticCoolingEnabled || settings.renderCoolingEnabled, active: coordinator.isForcedCoolingActive,
                available: coordinator.canUseForcedCooling, helperInstalled: coordinator.isFanHelperInstalled,
                blockedByLowBattery: coordinator.isCoolingBlockedByLowBattery,
                durationSeconds: Int(settings.forcedCoolingDuration),
                remainingSeconds: coordinator.forcedCoolingEndDate.map { max(0, Int(ceil($0.timeIntervalSinceNow))) } ?? 0,
                timerEndsAt: coordinator.forcedCoolingEndDate,
                automaticSpeed: speedPercent(settings.automaticCoolingFanMode),
                manualSpeed: speedPercent(settings.manualCoolingFanMode), onlyOnAC: settings.onlyOnACPower,
                fanControl: coordinator.fanController.activeMode == .auto ? "auto" : "\(speedPercent(coordinator.fanController.activeMode))%",
                error: coordinator.fanController.controlError,
                automaticEnabled: settings.automaticCoolingEnabled,
                automaticActive: coordinator.isAutomaticCoolingActive,
                manualArmed: settings.coolingArmed,
                manualActive: coordinator.isManualCoolingActive,
                renderEnabled: settings.renderCoolingEnabled,
                renderActive: coordinator.isRenderCoolingActive
            ),
            waitingForActivity: !coordinator.isActive && (
                settings.agentMonitoringEnabled || settings.downloadMonitoringEnabled
            ),
            manualActive: coordinator.isManualKeepAwakeActive,
            agentMonitoringEnabled: settings.agentMonitoringEnabled,
            downloadMonitoringEnabled: settings.downloadMonitoringEnabled,
            agentActive: coordinator.isAgentKeepAwakeActive,
            downloadActive: coordinator.isDownloadKeepAwakeActive
        )
    }
}
