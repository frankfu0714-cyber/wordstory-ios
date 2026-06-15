#if DEBUG
import Foundation
import SwiftData

/// Demo-data seeder used to produce App Store marketing screenshots.
///
/// Activates only in DEBUG builds and only when the process is launched with
/// the `--seedDemo` argument (set by the UI test runner). On first activation
/// it wipes any existing `Word` and `SavedStory` rows, then inserts a known
/// set so the screenshots look the same every time.
///
/// Also stashes a JSON-encoded `APIService.GenerateResponse` in
/// `UserDefaults` under `seedDemo.story` so `StoryView` can hydrate a
/// pre-generated story without round-tripping through the live Gemini API.
enum SeedDemo {

    static let isActive: Bool = ProcessInfo.processInfo.arguments.contains("--seedDemo")

    /// The vocabulary words that get pre-populated. Definitions ride along so
    /// we don't have to wait on a network or local-dictionary lookup during
    /// the screenshot run.
    struct WordSeed {
        let source: String
        let definition: String
        let example: String
        let learned: Bool
    }

    static let words: [WordSeed] = [
        WordSeed(
            source: "serendipity",
            definition: "意外的好運；意外發現美好事物的機緣",
            example: "Finding that old book at the flea market was pure serendipity.",
            learned: false
        ),
        WordSeed(
            source: "ephemeral",
            definition: "短暫的；轉瞬即逝的",
            example: "The cherry blossoms are beautiful but ephemeral.",
            learned: false
        ),
        WordSeed(
            source: "glossy",
            definition: "光滑的；有光澤的",
            example: "She turned the glossy page of the magazine.",
            learned: false
        ),
        WordSeed(
            source: "look forward to",
            definition: "期待；盼望",
            example: "I look forward to seeing you next week.",
            learned: false
        ),
        WordSeed(
            source: "redact",
            definition: "編輯；刪改（敏感內容）",
            example: "Several names had been redacted from the document.",
            learned: true
        ),
        WordSeed(
            source: "felonious",
            definition: "重罪的；犯罪的",
            example: "The judge described it as a felonious act.",
            learned: false
        ),
        WordSeed(
            source: "wistful",
            definition: "若有所思的；惆悵的",
            example: "He gave a wistful smile as he looked at the old photograph.",
            learned: false
        ),
        WordSeed(
            source: "vandalize",
            definition: "故意破壞（公物）",
            example: "Someone vandalized the statue overnight.",
            learned: false
        ),
    ]

    /// The story that `StoryView` will display when seedDemo is active.
    /// Five short sentences using five of the seed words above. Hand-written
    /// rather than generated so the wording stays consistent across runs.
    static let demoStory = APIService.GenerateResponse(
        sentences: [
            .init(
                en: "She turned the glossy page of the book, expecting nothing in particular.",
                zh: "她翻過書頁，那光滑的紙面上並沒有預期會看見什麼。"
            ),
            .init(
                en: "It was pure serendipity — a folded letter slipped out, the ink still slightly glossy.",
                zh: "純粹是一個美麗的巧合——一封摺起的信滑落下來，墨水仍隱隱泛著光澤。"
            ),
            .init(
                en: "She did not redact a single line of it as she copied it into her notebook.",
                zh: "她抄入筆記本時一字未刪。"
            ),
            .init(
                en: "The moment felt ephemeral, like a piece of mist she had to hold in her hands.",
                zh: "那一刻顯得短暫而易逝，彷彿她得用雙手捧住的一縷霧。"
            ),
            .init(
                en: "Already she could look forward to the rest of the afternoon with the letter tucked safely in her bag.",
                zh: "她已能期待整個下午都伴隨著這封安放在背包裡的信。"
            ),
        ],
        story_en: "She turned the glossy page of the book, expecting nothing in particular. It was pure serendipity — a folded letter slipped out, the ink still slightly glossy. She did not redact a single line of it as she copied it into her notebook. The moment felt ephemeral, like a piece of mist she had to hold in her hands. Already she could look forward to the rest of the afternoon with the letter tucked safely in her bag.",
        story_zh: "她翻過書頁，那光滑的紙面上並沒有預期會看見什麼。純粹是一個美麗的巧合——一封摺起的信滑落下來，墨水仍隱隱泛著光澤。她抄入筆記本時一字未刪。那一刻顯得短暫而易逝，彷彿她得用雙手捧住的一縷霧。她已能期待整個下午都伴隨著這封安放在背包裡的信。"
    )

    /// Second demo story for the Saved tab — different vocab + tone.
    static let demoStory2 = APIService.GenerateResponse(
        sentences: [
            .init(
                en: "The headline said someone had felonious intent.",
                zh: "頭條寫著——某人懷有犯罪意圖。"
            ),
            .init(
                en: "Whoever it was had vandalized the old library wall in the dead of night.",
                zh: "那人在深夜中破壞了舊圖書館的牆面。"
            ),
            .init(
                en: "The librarian's smile was wistful as she swept up the broken glass at dawn.",
                zh: "館員在黎明時掃起碎玻璃，臉上是若有所思的神情。"
            ),
        ],
        story_en: "The headline said someone had felonious intent. Whoever it was had vandalized the old library wall in the dead of night. The librarian's smile was wistful as she swept up the broken glass at dawn.",
        story_zh: "頭條寫著——某人懷有犯罪意圖。那人在深夜中破壞了舊圖書館的牆面。館員在黎明時掃起碎玻璃，臉上是若有所思的神情。"
    )

    /// Wipe existing data and re-insert the seed set. Called once on app
    /// launch in `wordstoryApp`.
    @MainActor
    static func seed(into ctx: ModelContext) {
        guard isActive else { return }

        // Wipe existing rows so screenshots are deterministic.
        if let existingWords = try? ctx.fetch(FetchDescriptor<Word>()) {
            for w in existingWords { ctx.delete(w) }
        }
        if let existingStories = try? ctx.fetch(FetchDescriptor<SavedStory>()) {
            for s in existingStories { ctx.delete(s) }
        }

        // Insert seed words, oldest first so the most recent shows on top of the list.
        let now = Date()
        for (i, seed) in words.enumerated() {
            let w = Word(
                sourceText: seed.source,
                definition: seed.definition,
                example: seed.example,
                learned: seed.learned,
                direction: .enToZh,
                addedDate: now.addingTimeInterval(-Double((words.count - 1 - i) * 60))
            )
            ctx.insert(w)
        }

        // Encode the demo Story view payload so StoryView can hydrate it.
        if let data = try? JSONEncoder().encode(demoStory) {
            UserDefaults.standard.set(data, forKey: "seedDemo.story")
        }
        // Pin the indexes (0-4) of the words used in the demo story so
        // StoryView can highlight them. We'll resolve them to ids on appear.
        UserDefaults.standard.set(
            ["serendipity", "ephemeral", "glossy", "look forward to", "redact"],
            forKey: "seedDemo.storyVocab"
        )

        // Insert two saved stories so the Saved tab has visible rows.
        if let data1 = try? JSONEncoder().encode(demoStory.sentences) {
            let json1 = String(data: data1, encoding: .utf8) ?? "[]"
            let s1 = SavedStory(
                dateCreated: now.addingTimeInterval(-3600 * 24),
                style: .shortStory,
                direction: .enToZh,
                sentencesJSON: json1,
                vocabIDs: [],
                titlePreview: String(demoStory.story_en.prefix(40)),
                storyEnFull: demoStory.story_en,
                storyZhFull: demoStory.story_zh
            )
            ctx.insert(s1)
        }
        if let data2 = try? JSONEncoder().encode(demoStory2.sentences) {
            let json2 = String(data: data2, encoding: .utf8) ?? "[]"
            let s2 = SavedStory(
                dateCreated: now.addingTimeInterval(-3600 * 48),
                style: .newsArticle,
                direction: .enToZh,
                sentencesJSON: json2,
                vocabIDs: [],
                titlePreview: String(demoStory2.story_en.prefix(40)),
                storyEnFull: demoStory2.story_en,
                storyZhFull: demoStory2.story_zh
            )
            ctx.insert(s2)
        }

        try? ctx.save()
    }
}
#endif
