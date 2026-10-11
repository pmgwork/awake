import Foundation

public nonisolated enum UpdateChannel: String, Sendable {
    case stable
    case beta

    static let preferenceKey = "pmgwork.awake.receiveBetaUpdates"

    var feedURL: String {
        "https://raw.githubusercontent.com/PMGWork/awake/update-feeds/\(rawValue).xml"
    }

    static func stored(in defaults: UserDefaults = .standard) -> UpdateChannel {
        defaults.bool(forKey: preferenceKey) ? .beta : .stable
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(self == .beta, forKey: Self.preferenceKey)
    }
}
