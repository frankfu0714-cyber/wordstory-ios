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
    var titlePreview: String
    /// Full concatenated English story (fallback render + previewing).
    var storyEnFull: String
    /// Full concatenated Traditional Chinese story (fallback render).
    var storyZhFull: String
    /// Original custom prompt — kept so retries on a failed custom-style
    /// generation can reconstitute the exact request. Empty for the
    /// built-in styles. Default makes this a lightweight migration.
    var customPromptStored: String = ""
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
        storyEnFull: String = "",
        storyZhFull: String = "",
        customPromptStored: String = "",
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
        self.storyEnFull = storyEnFull
        self.storyZhFull = storyZhFull
        self.customPromptStored = customPromptStored
        self.isGenerating = isGenerating
        self.generationFailed = generationFailed
        self.generationFailureReason = generationFailureReason
    }

    var style: StoryStyle {
        StoryStyle(rawValue: styleRaw) ?? .shortStory
    }

    var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
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
