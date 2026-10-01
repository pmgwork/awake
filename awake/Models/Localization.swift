//
//  Localization.swift
//  Awake
//

import Foundation

public nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case japanese = "ja"

    static let preferenceKey = "pmgwork.awake.language"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return L10n.string("System Default")
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }

    public var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    public static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}

public nonisolated enum L10n {
    public static func string(_ key: String, language: AppLanguage = .stored()) -> String {
        if language == .system {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            // English source keys are the fallback when there is no en.lproj.
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, language: AppLanguage = .stored(), _ arguments: CVarArg...) -> String {
        String(format: string(key, language: language), locale: language.locale, arguments: arguments)
    }
}
