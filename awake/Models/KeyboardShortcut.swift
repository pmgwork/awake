//
//  KeyboardShortcut.swift
//  Awake
//

import AppKit
import Carbon.HIToolbox

/// A single global keyboard shortcut.
///
/// `keyCode` is a hardware key code (`kVK_*`), so the shortcut keeps working
/// when the keyboard layout changes. `modifiers` stores only the modifiers
/// Awake supports: Command, Option, Control, and Shift.
public nonisolated struct KeyboardShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.supportedModifiers).rawValue
    }

    public static let supportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    /// Global shortcuts require a non-Shift modifier so they never fire while
    /// the user is simply typing text.
    public var isValid: Bool {
        modifierFlags.contains(.command)
            || modifierFlags.contains(.option)
            || modifierFlags.contains(.control)
    }

    /// Modifier symbols in the order macOS uses: ⌃⌥⇧⌘.
    public var modifierSymbols: String {
        var symbols = ""
        if modifierFlags.contains(.control) { symbols += "⌃" }
        if modifierFlags.contains(.option) { symbols += "⌥" }
        if modifierFlags.contains(.shift) { symbols += "⇧" }
        if modifierFlags.contains(.command) { symbols += "⌘" }
        return symbols
    }

    public var displayString: String {
        modifierSymbols + Self.keyName(for: keyCode)
    }

    /// Carbon representation consumed by `RegisterEventHotKey`.
    public var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifierFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifierFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    // MARK: - Key Names

    /// Human-readable name for a hardware key code, resolved with the current
    /// keyboard layout for printable keys.
    public static func keyName(for keyCode: UInt16) -> String {
        if let name = specialKeyNames[Int(keyCode)] {
            return name
        }
        if let character = layoutCharacter(for: keyCode), !character.isEmpty {
            // macOS displays Shift+Command+A as ⇧⌘A, so show the capital form
            // whenever the layout maps the key to a single cased character.
            return character.uppercased().count == 1 ? character.uppercased() : character
        }
        return "?"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Space: "Space",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12",
        kVK_F13: "F13",
        kVK_F14: "F14",
        kVK_F15: "F15",
        kVK_F16: "F16",
        kVK_F17: "F17",
        kVK_F18: "F18",
        kVK_F19: "F19",
        kVK_F20: "F20"
    ]

    private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }

            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )

            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
