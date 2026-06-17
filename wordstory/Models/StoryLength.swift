import Foundation

/// Orthogonal to `StoryStyle`: how long should the generated piece be?
///
/// - `.standard` — preserves the existing per-style word targets
///   (~150 words for short story / dialogue / letter, ~200 for news,
///   12–20 lines for poem). This is what the app shipped with.
/// - `.brief` — overrides the style's word target with a tight 40–60
///   word ceiling. Still uses every selected vocab word; the model is
///   instructed to drop padding rather than meet the longer count.
///   Use when the selected vocab list is short and a standard-length
///   piece would feel padded.
enum StoryLength: String, CaseIterable, Codable, Identifiable {
    case standard
    case brief

    var id: String { rawValue }

    /// LocalizedStringKey-friendly key string. Same pattern as
    /// `StoryStyle.titleKeyString` so SwiftUI views can wrap them in
    /// `LocalizedStringKey(...)` and respect same-session language
    /// switches.
    var titleKeyString: String {
        switch self {
        case .standard: return "length.standard"
        case .brief:    return "length.brief"
        }
    }
}
