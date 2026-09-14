//
//  GlobalShortcutManager.swift
//  Awake
//

import AppKit
import Carbon.HIToolbox
import Combine

private enum GlobalShortcutHotKey {
    static let signature: OSType = 0x4157_4B45 // 'AWKE'
    static let toggleID: UInt32 = 1
}

/// Registers a single system-wide hot key through Carbon.
///
/// Carbon hot keys are delivered before the event reaches the active app and
/// do not require Accessibility permission, so Awake keeps its current
/// permission footprint.
@MainActor
public final class GlobalShortcutManager: ObservableObject {
    public static let shared = GlobalShortcutManager()

    /// True while the persisted shortcut is registered with the system.
    @Published public private(set) var isRegistered = false
    /// User-facing reason the last registration attempt failed.
    @Published public private(set) var registrationError: String?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var toggleAction: (() -> Void)?

    private init() {}

    /// Replaces the registered toggle shortcut. Passing `nil` removes it.
    /// The action runs on the main actor every time the hot key is pressed.
    public func register(_ shortcut: KeyboardShortcut?, action: @escaping () -> Void) {
        unregisterHotKey()
        toggleAction = action

        guard let shortcut, shortcut.isValid else {
            registrationError = nil
            return
        }

        installEventHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(
            signature: GlobalShortcutHotKey.signature,
            id: GlobalShortcutHotKey.toggleID
        )
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            registrationError = L10n.string("This shortcut is already in use by another app or the system.")
            NSLog("[GlobalShortcutManager] RegisterEventHotKey failed with status %d.", status)
            return
        }

        hotKeyRef = ref
        isRegistered = true
        registrationError = nil
    }

    fileprivate func invokeToggleAction() {
        toggleAction?()
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        isRegistered = false
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            globalShortcutEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        if status != noErr {
            NSLog("[GlobalShortcutManager] InstallEventHandler failed with status %d.", status)
        }
    }
}

private let globalShortcutEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == GlobalShortcutHotKey.signature,
          hotKeyID.id == GlobalShortcutHotKey.toggleID else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.invokeToggleAction()
    }
    return noErr
}
