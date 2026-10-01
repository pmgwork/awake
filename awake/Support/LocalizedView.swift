import SwiftUI

/// Rebuilds localized content when the app preference changes while keeping
/// the view's identity and supplying the same locale to native SwiftUI controls.
struct LocalizedView<Content: View>: View {
    @ObservedObject private var settings = SettingsStore.shared
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .environment(\.locale, settings.language.locale)
    }
}
