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
    /// User-typed override for the Chinese meaning. nil = use the ECDICT/API
    /// `definition`; non-nil + trimmed-non-empty = render this instead.
    /// Default makes this a lightweight migration for pre-feature rows.
    /// Resetting via "Reset to dictionary" clears this back to nil so the
    /// original `definition` takes over again.
    var customDefinition: String? = nil

    init(
        id: UUID = UUID(),
        sourceText: String,
        definition: String = "",
        example: String = "",
        learned: Bool = false,
        direction: LanguageDirection,
        addedDate: Date = .now,
        definitionFetchFailed: Bool = false,
        customDefinition: String? = nil
    ) {
        self.id = id
        self.sourceText = sourceText
        self.definition = definition
        self.example = example
        self.learned = learned
        self.directionRaw = direction.rawValue
        self.addedDate = addedDate
        self.definitionFetchFailed = definitionFetchFailed
        self.customDefinition = customDefinition
    }

    var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
    }

    /// The definition the user actually sees: their override when set
    /// (trimmed-non-empty), otherwise the ECDICT/API `definition`.
    var effectiveDefinition: String {
        if let custom = customDefinition?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return definition
    }

    var hasCustomDefinition: Bool {
        guard let custom = customDefinition?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !custom.isEmpty
    }
}
