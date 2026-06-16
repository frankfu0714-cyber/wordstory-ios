import Foundation

enum StoryStyle: String, CaseIterable, Codable, Identifiable {
    case shortStory  = "short_story"
    case newsArticle = "news_article"
    case dialogue    = "dialogue"
    case letter      = "letter"
    case poem        = "poem"
    case custom      = "custom"

    var id: String { rawValue }

    /// Raw key strings, exposed so SwiftUI `Text` views can wrap them in
    /// `LocalizedStringKey(...)` and pick up the `\.locale` environment
    /// the app root sets in same-session language switches. `String(localized:)`
    /// reads `Bundle.main` instead, which only refreshes on next launch.
    var titleKeyString: String {
        switch self {
        case .shortStory:  return "style.short_story.title"
        case .newsArticle: return "style.news_article.title"
        case .dialogue:    return "style.dialogue.title"
        case .letter:      return "style.letter.title"
        case .poem:        return "style.poem.title"
        case .custom:      return "style.custom.title"
        }
    }

    var descriptionKeyString: String {
        switch self {
        case .shortStory:  return "style.short_story.description"
        case .newsArticle: return "style.news_article.description"
        case .dialogue:    return "style.dialogue.description"
        case .letter:      return "style.letter.description"
        case .poem:        return "style.poem.description"
        case .custom:      return "style.custom.description"
        }
    }

    /// Retained for any caller that still needs a Foundation-resolved
    /// string (e.g. when building a `String` that goes into a format).
    /// Prefer `titleKeyString` + `Text(LocalizedStringKey(...))` in SwiftUI.
    var titleKey: String.LocalizationValue { .init(stringLiteral: titleKeyString) }
    var descriptionKey: String.LocalizationValue { .init(stringLiteral: descriptionKeyString) }
}
