import SwiftUI
import SwiftData

/// Read-only render of a `SavedStory`. Same sentence-pair interleaving + Show
/// Chinese toggle as the live StoryView, but with no generate / save controls.
/// Looks up the vocabulary `Word` records by id so highlights still work when
/// reopened — and falls through to a name-only label if a referenced word has
/// since been deleted.
struct SavedStoryDetail: View {
    let story: SavedStory
    @Query private var allWords: [Word]
    @State private var showChinese: Bool = false
    @State private var tappedWord: Word?

    private var vocab: [Word] {
        let ids = Set(story.vocabIDs)
        return allWords.filter { ids.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                metaHeader

                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showChinese.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showChinese ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(showChinese ? "story.hide_chinese" : "story.show_chinese")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(showChinese ? Color.white : Color.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(showChinese ? Color.accentColor : Color.accentColor.opacity(0.10))
                        )
                        .overlay(
                            Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                if !story.sentences.isEmpty {
                    interleaved(story.sentences)
                } else {
                    // Fallback render for legacy saves (none yet, but defensive).
                    Text(makeAttributedStory(text: story.storyEnFull, words: vocab))
                        .font(Theme.serif(18))
                        .lineSpacing(8)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    if showChinese, !story.storyZhFull.isEmpty {
                        Text(makeChineseAttributed(text: story.storyZhFull, words: vocab))
                            .font(.system(size: 14))
                            .lineSpacing(5)
                            .foregroundStyle(Theme.inkSoft)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(story.titlePreview.isEmpty ? "—" : story.titlePreview + "…")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $tappedWord) { word in
            WordDetailModal(word: word)
                .presentationDetents([.medium])
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "wordstory",
               let last = url.pathComponents.last,
               let id = UUID(uuidString: last),
               let word = vocab.first(where: { $0.id == id }) {
                tappedWord = word
                return .handled
            }
            return .systemAction
        })
    }

    private var metaHeader: some View {
        HStack(spacing: 8) {
            Text(String(localized: story.style.titleKey))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.10)))
                .foregroundStyle(Color.accentColor)
            Text("\(story.direction.targetDisplayName) → \(story.direction.nativeDisplayName)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.paperSoft))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(story.dateCreated, format: .dateTime.month(.abbreviated).day().year())
                .font(.caption)
                .foregroundStyle(Theme.inkQuiet)
        }
    }

    private func interleaved(_ sentences: [APIService.GenerateResponse.SentencePair]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: showChinese ? 3 : 0) {
                    Text(makeAttributedStory(text: pair.en, words: vocab))
                        .font(Theme.serif(18))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    if showChinese {
                        Text(makeChineseAttributed(text: pair.zh, words: vocab))
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.inkSoft)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: - Highlight helpers (mirrors StoryView's implementations)

    private func makeAttributedStory(text: String, words: [Word]) -> AttributedString {
        var attr = AttributedString(text)
        let nsText = text as NSString
        let sorted = words.sorted { $0.sourceText.count > $1.sourceText.count }
        var covered: [NSRange] = []
        for word in sorted {
            let trimmed = word.sourceText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let pattern: String
            if containsCJK(trimmed) {
                pattern = NSRegularExpression.escapedPattern(for: trimmed)
            } else {
                let esc = NSRegularExpression.escapedPattern(for: trimmed)
                pattern = "\\b\(esc)(?:[a-zA-Z]{0,4})?\\b"
            }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                if covered.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
                covered.append(match.range)
                guard let range = Range<AttributedString.Index>(match.range, in: attr) else { continue }
                attr[range].foregroundColor = .accentColor
                attr[range].underlineStyle = .single
                attr[range].link = URL(string: "wordstory://word/\(word.id.uuidString)")
            }
        }
        return attr
    }

    private func makeChineseAttributed(text: String, words: [Word]) -> AttributedString {
        var attr = AttributedString(text)
        let nsText = text as NSString
        var lookups: [(candidate: String, word: Word)] = []
        for word in words {
            for cand in chineseCandidates(for: word) {
                lookups.append((cand, word))
            }
        }
        lookups.sort { $0.candidate.count > $1.candidate.count }
        var covered: [NSRange] = []
        for (cand, word) in lookups {
            let escaped = NSRegularExpression.escapedPattern(for: cand)
            guard let regex = try? NSRegularExpression(pattern: escaped) else { continue }
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                if covered.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
                covered.append(match.range)
                guard let range = Range<AttributedString.Index>(match.range, in: attr) else { continue }
                attr[range].foregroundColor = .accentColor
                attr[range].underlineStyle = .single
                attr[range].link = URL(string: "wordstory://word/\(word.id.uuidString)")
            }
        }
        return attr
    }

    private func chineseCandidates(for word: Word) -> [String] {
        let posPrefixPattern = #"^(?:[a-zA-Z]+\.|\[[^\]]+\])\s*"#
        var out: Set<String> = []
        for line in word.definition.components(separatedBy: "\n") {
            let stripped = line.replacingOccurrences(
                of: posPrefixPattern,
                with: "",
                options: .regularExpression
            )
            let delim = CharacterSet(charactersIn: ",;、，；/／")
            for raw in stripped.components(separatedBy: delim) {
                let s = raw.trimmingCharacters(in: .whitespaces)
                guard (1...8).contains(s.count), containsCJK(s) else { continue }
                out.insert(s)
            }
        }
        return Array(out)
    }

    private func containsCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            (0x3400...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
