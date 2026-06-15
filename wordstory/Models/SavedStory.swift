import Foundation
import SwiftData

/// A story the user has chosen to keep. Stored under SwiftData alongside
/// `Word` so saves persist across launches.
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
    /// `[SentencePair]` encoded as a JSON UTF-8 string.
    var sentencesJSON: String
    /// `Word.id` values for the vocabulary the story was generated against.
    /// Re-rendering looks them up by id so highlights still work if any of
    /// the underlying words were edited after saving.
    var vocabIDs: [UUID]
    /// First ~40 chars of the English story for the list row label.
    var titlePreview: String
    /// Full concatenated English story (fallback render + previewing).
    var storyEnFull: String
    /// Full concatenated Traditional Chinese story (fallback render).
    var storyZhFull: String

    init(
        id: UUID = UUID(),
        dateCreated: Date = .now,
        style: StoryStyle,
        direction: LanguageDirection,
        sentencesJSON: String,
        vocabIDs: [UUID],
        titlePreview: String,
        storyEnFull: String,
        storyZhFull: String
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
