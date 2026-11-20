/// External displays remain usable with the lid closed. Only a closed Mac
/// without an external display should suppress screen-related assertions.
struct DisplayBehaviorPolicy {
    let lidClosed: Bool
    let hasExternalDisplay: Bool

    /// Manual cooling is user initiated, so it runs in every display
    /// configuration, including native clamshell. Automatic cooling is
    /// limited to headless closed-lid operation.
    func allowsCooling(for mode: CoolingMode) -> Bool {
        switch mode {
        case .forced, .timed:
            return true
        case .whileKeepAwakeIsOn:
            return allowsAutomaticCooling
        }
    }

    /// Automatic cooling is limited to headless closed-lid operation.
    func requestsAutomaticCooling(keepAwakeActive: Bool, onlyOnACPower: Bool, isOnACPower: Bool) -> Bool {
        keepAwakeActive && allowsAutomaticCooling && (!onlyOnACPower || isOnACPower)
    }

    var allowsAutomaticCooling: Bool { lidClosed && !hasExternalDisplay }

    var allowsScreenPrevention: Bool { !lidClosed || hasExternalDisplay }

    /// Whether SleepManager should take closed-lid system-sleep assertions.
    /// Requires the user's closed-lid opt-in and an available helper. It also
    /// applies with an external display: unplugging that display with the lid
    /// closed would otherwise sleep the Mac at once, and AirPlay, Sidecar, and
    /// virtual displays count as external but don't keep a closed Mac awake.
    func preventsClosedLidSleep(closedDisplayModeEnabled: Bool, helperAvailable: Bool) -> Bool {
        closedDisplayModeEnabled && helperAvailable && lidClosed
    }
}
