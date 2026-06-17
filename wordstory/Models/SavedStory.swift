import Foundation
import SwiftData

/// A story the user has chosen to keep. Stored under SwiftData alongside
/// `Word` so saves persist across launches.
///
/// As of the auto-save flow, generations also start life as a SavedStory:
/// the model is inserted with `isGenerating = true` and empty content
/// fields, and the body is populated when the API call resolves. Failed
/// generations stay around with `generationFailed = true` so the user can
/// see and retry them from the Saved tab.
///
/// Sentence pairs are JSON-encoded into a single String column because
/// SwiftData's `[Codable struct]` storage has a history of quirks — encoding
/// to a string keeps the read/write contract simple and round-trippable.
@Model
final class SavedStory {
    @Attribute(.unique) var id: UUID
    var dateCreated: Date
    /// Raw value of `StoryStyle` (short_story / news_article / dialogue / …).
    var styleRaw: String
    /// Raw value of `LanguageDirection` (en-to-zh / zh-to-en).
    var directionRaw: String
    /// `[SentencePair]` encoded as a JSON UTF-8 string. Empty `""` while
    /// generating; the renderer falls back to `storyEnFull` / `storyZhFull`.
    var sentencesJSON: String
    /// `Word.id` values for the vocabulary the story was generated against.
    /// Re-rendering looks them up by id so highlights still work if any of
    /// the underlying words were edited after saving.
    var vocabIDs: [UUID]
    /// First ~40 chars of the English story for the list row label. Empty
    /// while generating (the row shows a "Generating…" label instead).
    /// Used as the FALLBACK title — `customTitle` overrides when set.
    var titlePreview: String
    /// User-set title — overrides `titlePreview` everywhere it's displayed.
    /// nil = no override (show the auto preview). Default makes this a
    /// lightweight migration for pre-feature saves.
    var customTitle: String?
    /// Full concatenated English story (fallback render + previewing).
    var storyEnFull: String
    /// Full concatenated Traditional Chinese story (fallback render).
    var storyZhFull: String
    /// Original custom prompt — kept so retries on a failed custom-style
    /// generation can reconstitute the exact request. Empty for the
    /// built-in styles. Default makes this a lightweight migration.
    var customPromptStored: String = ""
    /// Raw value of `StoryLength` (`standard` / `brief`). Defaults to the
    /// pre-feature value so legacy rows decode as `.standard` and the
    /// regenerate flow preserves whichever length the source story used.
    var lengthRaw: String = StoryLength.standard.rawValue
    /// True while the API call is in-flight. The Saved tab shows a spinner
    /// row and the detail view shows a "Generating…" placeholder. Cleared
    /// to false once the call resolves (success or failure).
    var isGenerating: Bool = false
    /// True if the API call returned an error. Mutually exclusive with
    /// isGenerating — only one of {isGenerating, generationFailed, success}
    /// is true at a time.
    var generationFailed: Bool = false
    /// Human-readable error string for the failed-row's retry UI / debug.
    var generationFailureReason: String?

    init(
        id: UUID = UUID(),
        dateCreated: Date = .now,
        style: StoryStyle,
        direction: LanguageDirection,
        sentencesJSON: String = "",
        vocabIDs: [UUID],
        titlePreview: String = "",
        customTitle: String? = nil,
        storyEnFull: String = "",
        storyZhFull: String = "",
        customPromptStored: String = "",
        length: StoryLength = .standard,
        isGenerating: Bool = false,
        generationFailed: Bool = false,
        generationFailureReason: String? = nil
    ) {
        self.id = id
        self.dateCreated = dateCreated
        self.styleRaw = style.rawValue
        self.directionRaw = direction.rawValue
        self.sentencesJSON = sentencesJSON
        self.vocabIDs = vocabIDs
        self.titlePreview = titlePreview
        self.customTitle = customTitle
        self.storyEnFull = storyEnFull
        self.storyZhFull = storyZhFull
        self.customPromptStored = customPromptStored
        self.lengthRaw = length.rawValue
        self.isGenerating = isGenerating
        self.generationFailed = generationFailed
        self.generationFailureReason = generationFailureReason
    }

    /// The label to show wherever the story's title appears. Prefers the
    /// user-set `customTitle` (trimmed, non-empty); falls back to the
    /// `titlePreview` auto-derived from the story body.
    var displayTitle: String {
        if let custom = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return titlePreview
    }

    var style: StoryStyle {
        StoryStyle(rawValue: styleRaw) ?? .shortStory
    }

    var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
    }

    var length: StoryLength {
        StoryLength(rawValue: lengthRaw) ?? .standard
    }

    /// Decoded sentence pairs. Returns an empty array if the stored JSON is
    /// malformed (shouldn't happen — we control the encoder — but safer than
    /// throwing during view rendering).
    var sentences: [APIService.GenerateResponse.SentencePair] {
        guard let data = sentencesJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode(
            [APIService.GenerateResponse.SentencePair].self,
            from: data
        )) ?? []
    }
}
