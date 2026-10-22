/// External displays remain usable with the lid closed. Only a closed Mac
/// without an external display should suppress screen-related assertions.
struct DisplayBehaviorPolicy {
    let lidClosed: Bool
    let hasExternalDisplay: Bool

    /// Manual cooling is user initiated, so it runs in every display
    /// configuration, including native clamshell. Automatic agent cooling is
    /// limited to headless closed-lid operation.
    func allowsCooling(for mode: CoolingMode) -> Bool {
        switch mode {
        case .forced, .timed:
            return true
        case .whileAgentRunning:
            return allowsAgentCooling
        }
    }

    /// Agent cooling is limited to headless closed-lid operation.
    var allowsAgentCooling: Bool { lidClosed && !hasExternalDisplay }

    var allowsScreenPrevention: Bool { !lidClosed || hasExternalDisplay }

    // Native clamshell mode already handles external displays. Changing its
    // lid-sleep override can interrupt the active display session. Keep the
    // override armed with the lid open only when no external display is attached.
    var needsClosedDisplayOverride: Bool { !hasExternalDisplay }
}
