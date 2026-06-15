import Foundation

/// Which language the user is learning, and which language definitions appear in.
/// `enToZh` means the vocabulary is English; definitions appear in 繁體中文.
/// `zhToEn` means the vocabulary is Chinese; definitions appear in English.
enum LanguageDirection: String, CaseIterable, Codable, Identifiable {
    case enToZh = "en-to-zh"
    case zhToEn = "zh-to-en"

    var id: String { rawValue }

    /// Display name for the target language (the vocabulary side).
    var targetDisplayName: String {
        switch self {
        case .enToZh: return "English"
        case .zhToEn: return "繁體中文"
        }
    }

    /// Display name for the native language (the definitions side).
    var nativeDisplayName: String {
        switch self {
        case .enToZh: return "繁體中文"
        case .zhToEn: return "English"
        }
    }

    var flipped: LanguageDirection {
        switch self {
        case .enToZh: return .zhToEn
        case .zhToEn: return .enToZh
        }
    }

    /// BCP-47 language code for the source word — the vocabulary side.
    /// Used by `SpeechService` to pick a voice for the pronunciation button.
    var sourceLanguageCode: String {
        switch self {
        case .enToZh: return "en-US"
        case .zhToEn: return "zh-TW"
        }
    }
}
