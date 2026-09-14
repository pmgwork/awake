import XCTest
import AppKit
import Carbon.HIToolbox
@testable import awake

final class KeyboardShortcutTests: XCTestCase {
    func testModifierSymbolsUseMacOrder() {
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(shortcut.modifierSymbols, "⌃⌥⇧⌘")
    }

    func testShortcutRequiresNonShiftModifier() {
        XCTAssertFalse(KeyboardShortcut(keyCode: 0, modifiers: []).isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 0, modifiers: [.shift]).isValid)
        XCTAssertTrue(KeyboardShortcut(keyCode: 0, modifiers: [.control]).isValid)
        XCTAssertTrue(KeyboardShortcut(keyCode: 0, modifiers: [.option]).isValid)
        XCTAssertTrue(KeyboardShortcut(keyCode: 0, modifiers: [.command]).isValid)
    }

    func testUnsupportedModifiersAreDropped() {
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .function, .capsLock, .numericPad])
        XCTAssertEqual(shortcut.modifierFlags, [.command])
        XCTAssertEqual(shortcut.modifiers, NSEvent.ModifierFlags.command.rawValue)
    }

    func testCarbonModifierConversion() {
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .option, .shift, .control])
        XCTAssertEqual(
            shortcut.carbonModifiers,
            UInt32(cmdKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(controlKey)
        )
    }

    func testSpecialKeyNamesAreStable() {
        XCTAssertEqual(KeyboardShortcut.keyName(for: UInt16(kVK_Space)), "Space")
        XCTAssertEqual(KeyboardShortcut.keyName(for: UInt16(kVK_Escape)), "⎋")
        XCTAssertEqual(KeyboardShortcut.keyName(for: UInt16(kVK_Return)), "↩")
        XCTAssertEqual(KeyboardShortcut.keyName(for: UInt16(kVK_LeftArrow)), "←")
        XCTAssertEqual(KeyboardShortcut.keyName(for: UInt16(kVK_F5)), "F5")
    }

    func testDisplayStringCombinesSymbolsAndKeyName() {
        let shortcut = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifiers: [.command, .shift])
        XCTAssertEqual(shortcut.displayString, "⇧⌘Space")
    }

    func testCodableRoundTrip() throws {
        let shortcut = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command, .option])
        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: data)
        XCTAssertEqual(decoded, shortcut)
        XCTAssertEqual(decoded.keyCode, shortcut.keyCode)
        XCTAssertEqual(decoded.modifiers, shortcut.modifiers)
    }

    @MainActor
    func testManagerRegistersAndClearsShortcut() {
        let manager = GlobalShortcutManager.shared
        let shortcut = KeyboardShortcut(
            keyCode: UInt16(kVK_F19),
            modifiers: [.command, .option, .shift, .control]
        )

        manager.register(shortcut) {}
        XCTAssertTrue(manager.isRegistered)
        XCTAssertNil(manager.registrationError)

        manager.register(nil) {}
        XCTAssertFalse(manager.isRegistered)
        XCTAssertNil(manager.registrationError)
    }
}
