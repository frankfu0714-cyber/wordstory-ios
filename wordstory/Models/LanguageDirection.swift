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

    /// Detect the appropriate direction from the input text itself, ignoring
    /// the user's global setting. Lets the add-bar autocomplete + submit
    /// flow handle mixed-language input without forcing the user into
    /// Settings to flip direction.
    ///
    /// Heuristic: >50% of non-whitespace characters in the CJK Unified
    /// Ideographs block → zh-to-en; otherwise en-to-zh. Empty input falls
    /// back to en-to-zh (the most common case).
    static func detect(for text: String) -> LanguageDirection {
        let nonWS = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !nonWS.isEmpty else { return .enToZh }
        // 0x4E00…0x9FFF is the CJK Unified Ideographs block — covers the
        // overwhelming majority of Han characters the user will type. We
        // intentionally don't include CJK Extensions A–F (the dictionary
        // doesn't index them) or Bopomofo/Kana (out of scope).
        let cjk = nonWS.filter { (0x4E00...0x9FFF).contains(Int($0.value)) }.count
        return Double(cjk) / Double(nonWS.count) > 0.5 ? .zhToEn : .enToZh
    }
}
