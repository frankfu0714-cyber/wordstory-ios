import Foundation

enum StoryStyle: String, CaseIterable, Codable, Identifiable {
    case shortStory  = "short_story"
    case newsArticle = "news_article"
    case dialogue    = "dialogue"
    case letter      = "letter"
    case poem        = "poem"
    case custom      = "custom"

    var id: String { rawValue }

    /// Localized title key for use with `String(localized:)`.
    var titleKey: String.LocalizationValue {
        switch self {
        case .shortStory:  return "style.short_story.title"
        case .newsArticle: return "style.news_article.title"
        case .dialogue:    return "style.dialogue.title"
        case .letter:      return "style.letter.title"
        case .poem:        return "style.poem.title"
        case .custom:      return "style.custom.title"
        }
    }

    var descriptionKey: String.LocalizationValue {
        switch self {
        case .shortStory:  return "style.short_story.description"
        case .newsArticle: return "style.news_article.description"
        case .dialogue:    return "style.dialogue.description"
        case .letter:      return "style.letter.description"
        case .poem:        return "style.poem.description"
        case .custom:      return "style.custom.description"
        }
    }
}
