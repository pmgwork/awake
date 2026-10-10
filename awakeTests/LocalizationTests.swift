import XCTest
@testable import awake

final class LocalizationTests: XCTestCase {
    func testEnglishAndJapaneseCanSwitchWithoutRestart() {
        XCTAssertEqual(L10n.string("Language", language: .english), "Language")
        XCTAssertEqual(L10n.string("Language", language: .japanese), "言語")
        XCTAssertEqual(L10n.string("Language", language: .english), "Language")
        XCTAssertEqual(L10n.string("System Default", language: .japanese), "システムに合わせる")
    }

    func testJapaneseFormattingAndMissingTranslationFallback() {
        XCTAssertEqual(L10n.format("%d running", language: .japanese, 2), "2件実行中")
        XCTAssertEqual(L10n.string("untranslated-key", language: .japanese), "untranslated-key")
    }

    func testLanguagePreferencePersistsAndInvalidValueUsesSystem() {
        let name = "pmgwork.awake.language-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
        defaults.set(AppLanguage.japanese.rawValue, forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.stored(in: UserDefaults(suiteName: name)!), .japanese)
        defaults.set("unsupported", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
    }

    func testSystemLanguageUsesBundlePreference() {
        XCTAssertEqual(
            L10n.string("General", language: .system),
            Bundle.main.localizedString(forKey: "General", value: "General", table: nil)
        )
    }
}
