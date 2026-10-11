/// External displays remain usable with the lid closed. Only a closed Mac
/// without an external display should suppress screen-related assertions.
struct DisplayBehaviorPolicy {
    let lidClosed: Bool
    let hasExternalDisplay: Bool

    var isNativeClamshell: Bool { lidClosed && hasExternalDisplay }

    /// Native clamshell operation leaves hardware control to macOS in every mode.
    var allowsCooling: Bool { !isNativeClamshell }

    /// Agent cooling is limited to headless closed-lid operation.
    var allowsAgentCooling: Bool { lidClosed && !hasExternalDisplay }

    var allowsScreenPrevention: Bool { !lidClosed || hasExternalDisplay }

    // Native clamshell mode already handles external displays. Changing its
    // lid-sleep override can interrupt the active display session. Keep the
    // override armed with the lid open only when no external display is attached.
    var needsClosedDisplayOverride: Bool { !hasExternalDisplay }
}
