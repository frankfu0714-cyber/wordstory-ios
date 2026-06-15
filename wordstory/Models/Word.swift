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

    init(
        id: UUID = UUID(),
        sourceText: String,
        definition: String = "",
        example: String = "",
        learned: Bool = false,
        direction: LanguageDirection,
        addedDate: Date = .now
    ) {
        self.id = id
        self.sourceText = sourceText
        self.definition = definition
        self.example = example
        self.learned = learned
        self.directionRaw = direction.rawValue
        self.addedDate = addedDate
    }

    var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
    }
}
