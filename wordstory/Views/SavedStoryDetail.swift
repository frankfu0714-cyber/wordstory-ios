import SwiftUI
import SwiftData

/// Read-only render of a `SavedStory`. Same sentence-pair interleaving + Show
/// Chinese toggle as the live StoryView used to do, but with no generate /
/// save controls — every generation lands here automatically. Looks up the
/// vocabulary `Word` records by id so highlights still work when reopened.
struct SavedStoryDetail: View {
    let story: SavedStory
    /// Optional callback for the toolbar "Regenerate" button. The parent
    /// list owns the dispatch logic (it has the SwiftData context + the
    /// allWords @Query handy); passing a closure keeps this view stateless
    /// about the regeneration flow. nil = hide the toolbar button.
    var onRegenerate: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var allWords: [Word]
    @State private var showChinese: Bool = false
    @State private var tappedWord: Word?
    @State private var isEditingTitle: Bool = false
    @State private var didRegenerate: Bool = false

    private var vocab: [Word] {
        let ids = Set(story.vocabIDs)
        return allWords.filter { ids.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                metaHeader

                if story.isGenerating {
                    generatingPlaceholder
                } else if story.generationFailed {
                    failedPlaceholder
                } else {
                    storyBody
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(navigationTitleString)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Regenerate + pencil only make sense once there's a story to
            // act on; hide them on placeholder/failed rows.
            if !story.isGenerating && !story.generationFailed {
                if let onRegenerate {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onRegenerate()
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                didRegenerate = true
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation { didRegenerate = false }
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityLabel(Text("saved.regenerate"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isEditingTitle = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(Text("saved.title.edit"))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if didRegenerate {
                Text("saved.regenerate.toast")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Theme.ink.opacity(0.92))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $isEditingTitle) {
            TitleEditSheet(story: story)
        }
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

    private var navigationTitleString: String {
        if story.isGenerating { return String(localized: "saved.generating") }
        if story.generationFailed { return String(localized: "saved.failed") }
        if let custom = story.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return story.titlePreview.isEmpty ? "—" : story.titlePreview + "…"
    }


    private var storyBody: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                // Fallback render for responses where the sentences[] array
                // was lost to truncation.
                Text(makeAttributedStory(text: story.storyEnFull, words: vocab))
                    .font(Theme.serif(18))
                    .lineSpacing(8)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                if showChinese, !story.storyZhFull.isEmpty {
                    Text(makeChineseAttributed(text: story.storyZhFull, words: vocab, spans: nil))
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .foregroundStyle(Theme.inkSoft)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var generatingPlaceholder: some View {
        VStack(alignment: .center, spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.accentColor)
            Text("saved.generating")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            if !vocab.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(vocab) { w in
                        Text(w.sourceText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.paperSoft))
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var failedPlaceholder: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.danger)
            Text("saved.failed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.danger)
            if let reason = story.generationFailureReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Theme.inkQuiet)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var metaHeader: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(story.style.titleKeyString))
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
                        Text(makeChineseAttributed(text: pair.zh, words: vocab, spans: pair.vocab_spans))
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.inkSoft)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: - Highlight helpers

    /// Highlights English vocab including INFLECTED forms of multi-word
    /// phrases. Splits the phrase on whitespace and allows each token a
    /// short optional suffix, so `look forward to` matches `look forward
    /// to`, `looked forward to`, `looking forward to`, `looks forward to`.
    /// Each token gets up to 4 trailing letters — same suffix budget the
    /// single-word matcher has always used.
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
                let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                let parts = tokens.map { token in
                    NSRegularExpression.escapedPattern(for: String(token)) + "(?:[a-zA-Z]{0,4})?"
                }
                pattern = "\\b" + parts.joined(separator: "\\s+") + "\\b"
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

    /// Prefers Gemini's per-sentence `vocab_spans` exact substring; falls
    /// back to dictionary-derived candidates when the span is missing.
    private func makeChineseAttributed(
        text: String,
        words: [Word],
        spans: [String: String]?
    ) -> AttributedString {
        var attr = AttributedString(text)
        let nsText = text as NSString
        var lookups: [(candidate: String, word: Word)] = []
        for word in words {
            let key = word.sourceText.trimmingCharacters(in: .whitespaces).lowercased()
            if let span = spans?[key],
               !span.trimmingCharacters(in: .whitespaces).isEmpty {
                lookups.append((span, word))
            } else {
                for cand in chineseCandidates(for: word) {
                    lookups.append((cand, word))
                }
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
        // Include both the dictionary definition and any user-typed override
        // so highlights still light up when the user has overridden the
        // meaning of a word that appeared in the story.
        let sources = [word.definition, word.customDefinition ?? ""]
        for source in sources where !source.isEmpty {
            for line in source.components(separatedBy: "\n") {
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
        }
        return Array(out)
    }

    private func containsCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            (0x3400...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
