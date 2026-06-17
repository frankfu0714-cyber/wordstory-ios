import SwiftUI
import SwiftData

@main
struct WordstoryApp: App {

    /// The user's chosen UI language ("en" / "zh") — empty means follow system.
    /// Stored in `AppleLanguages` to take effect on next launch; the env-locale below
    /// gives us same-session updates for the strings that respect it.
    @AppStorage("uiLanguage") private var uiLanguage: String = ""

    /// Pin nav-title text to brand ink. Without this, large titles inherit
    /// `.label`, which becomes near-white when the device is in dark mode
    /// — invisible against our cream `Theme.background`. Mirrors the values
    /// in `Theme.ink` (sRGB 0.16 / 0.145 / 0.125).
    init() {
        let ink = UIColor(red: 0.16, green: 0.145, blue: 0.125, alpha: 1.0)
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: ink]
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: ink]
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, currentLocale)
                .tint(Color.accentColor)
                #if DEBUG
                .modelContext_seedDemoIfNeeded()
                #endif
        }
        .modelContainer(for: [Word.self, SavedStory.self])
    }

    private var currentLocale: Locale {
        switch uiLanguage {
        case "en": return Locale(identifier: "en")
        case "zh": return Locale(identifier: "zh-Hant")
        default:   return Locale.current
        }
    }
}

#if DEBUG
private extension View {
    /// Hook for `SeedDemo.seed(_:)`. Runs once on first appear when the
    /// `--seedDemo` launch arg is present; no-op in production builds.
    func modelContext_seedDemoIfNeeded() -> some View {
        modifier(SeedDemoModifier())
    }
}

private struct SeedDemoModifier: ViewModifier {
    @Environment(\.modelContext) private var ctx
    @State private var didSeed = false
    func body(content: Content) -> some View {
        content.onAppear {
            guard SeedDemo.isActive, !didSeed else { return }
            didSeed = true
            SeedDemo.seed(into: ctx)
        }
    }
}
#endif
