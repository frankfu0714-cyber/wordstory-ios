import Foundation
import SwiftData

@Model
final class Word {
    @Attribute(.unique) var id: UUID
    var sourceText: String
    var definition: String
    var example: String
    var addedDate: Date
    var learned: Bool
    /// Stored as the raw value of `LanguageDirection` (the direction at which the word was added).
    var directionRaw: String
    /// True when the most recent attempt to fetch a definition from the API failed.
    /// Default false makes this a lightweight migration — older rows without the
    /// attribute load as not-failed, which is the right read for legacy data
    /// (we just won't know whether their empty definitions were a real failure).
    var definitionFetchFailed: Bool = false

    init(
        id: UUID = UUID(),
        sourceText: String,
        definition: String = "",
        example: String = "",
        learned: Bool = false,
        direction: LanguageDirection,
        addedDate: Date = .now,
        definitionFetchFailed: Bool = false
    ) {
        self.id = id
        self.sourceText = sourceText
        self.definition = definition
        self.example = example
        self.learned = learned
        self.directionRaw = direction.rawValue
        self.addedDate = addedDate
        self.definitionFetchFailed = definitionFetchFailed
    }

    var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
    }
}
