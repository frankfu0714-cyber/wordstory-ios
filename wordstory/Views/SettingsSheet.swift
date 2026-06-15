import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("uiLanguage") private var uiLanguage: String = ""
    @AppStorage("languageDirection") private var directionRaw = LanguageDirection.enToZh.rawValue

    @Query private var allWords: [Word]
    @State private var showClearConfirm = false
    @State private var showRestartHint = false

    private var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("settings.language.label", selection: $uiLanguage) {
                        Text("settings.language.system").tag("")
                        Text("English").tag("en")
                        Text("繁體中文").tag("zh")
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("settings.language.label")
                } footer: {
                    Text("settings.language.hint")
                        .font(.caption)
                        .foregroundStyle(Theme.inkQuiet)
                }
                .listRowBackground(Theme.paper)

                Section {
                    Button {
                        directionRaw = direction.flipped.rawValue
                    } label: {
                        HStack {
                            Text("settings.direction.learning")
                                .foregroundStyle(Theme.inkSoft)
                                .font(.subheadline)
                            Spacer()
                            Text(direction.targetDisplayName)
                                .foregroundStyle(Theme.ink)
                                .fontWeight(.medium)
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                            Text(direction.nativeDisplayName)
                                .foregroundStyle(Theme.inkSoft)
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("settings.direction.label")
                } footer: {
                    Text("settings.direction.hint")
                        .font(.caption)
                        .foregroundStyle(Theme.inkQuiet)
                }
                .listRowBackground(Theme.paper)

                Section("settings.about.label") {
                    HStack {
                        Text("settings.about.version")
                            .foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(Theme.inkQuiet)
                            .font(.system(.body, design: .monospaced))
                    }
                    Link(destination: URL(string: "https://goldotakutw.com/about")!) {
                        HStack {
                            Text("settings.about.feedback")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkQuiet)
                        }
                    }
                }
                .listRowBackground(Theme.paper)

                Section {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("settings.clear.button")
                        }
                    }
                    .disabled(allWords.isEmpty)
                } footer: {
                    Text("settings.clear.hint")
                        .font(.caption)
                        .foregroundStyle(Theme.inkQuiet)
                }
                .listRowBackground(Theme.paper)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert("settings.clear.confirm.title", isPresented: $showClearConfirm) {
                Button("action.cancel", role: .cancel) { }
                Button("settings.clear.confirm.confirm", role: .destructive) {
                    clearAll()
                }
            } message: {
                Text("settings.clear.confirm.message")
            }
            .onChange(of: uiLanguage) { _, _ in
                applyLanguagePreference()
            }
        }
    }

    private func clearAll() {
        for w in allWords { modelContext.delete(w) }
        try? modelContext.save()
    }

    /// Writes the chosen language to `AppleLanguages` so it persists across launches.
    /// `.environment(\.locale, ...)` at the app root handles same-session updates for
    /// strings that respect the locale environment.
    private func applyLanguagePreference() {
        let languages: [String] = switch uiLanguage {
        case "en": ["en"]
        case "zh": ["zh-Hant"]
        default:   []
        }
        if languages.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set(languages, forKey: "AppleLanguages")
        }
    }
}

#Preview {
    SettingsSheet()
        .modelContainer(for: Word.self, inMemory: true)
}
