import SwiftUI
import SwiftData

@main
struct WordstoryApp: App {

    /// The user's chosen UI language ("en" / "zh") — empty means follow system.
    /// Stored in `AppleLanguages` to take effect on next launch; the env-locale below
    /// gives us same-session updates for the strings that respect it.
    @AppStorage("uiLanguage") private var uiLanguage: String = ""

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, currentLocale)
                .tint(Color.accentColor)
        }
        .modelContainer(for: Word.self)
    }

    private var currentLocale: Locale {
        switch uiLanguage {
        case "en": return Locale(identifier: "en")
        case "zh": return Locale(identifier: "zh-Hant")
        default:   return Locale.current
        }
    }
}
