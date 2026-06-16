import SwiftUI
import SwiftData

/// A wrapping flow layout — used for the word chip selector.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + rowSpacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowHeight + rowSpacing; rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct StoryView: View {
    @Binding var showSettings: Bool
    @Query private var allWords: [Word]
    @Query private var savedStories: [SavedStory]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("languageDirection") private var directionRaw = LanguageDirection.enToZh.rawValue
    private var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
    }

    @State private var selectedIDs: Set<UUID> = []
    @State private var style: StoryStyle = .shortStory
    @State private var customPrompt = ""

    @State private var generated: APIService.GenerateResponse?
    @State private var generatedFor: [Word] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?

    @State private var tappedWord: Word?
    /// When true, each English sentence has its Chinese translation rendered
    /// directly below it. When false, only the English story shows.
    @State private var showChinese: Bool = false
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectorSection
                    styleSection
                    if style == .custom {
                        customPromptField
                    }
                    generateButton
                    if let errorMessage {
                        errorBanner(message: errorMessage)
                    }
                    if let generated {
                        storyOutput(generated: generated)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                #if DEBUG
                .onAppear { hydrateSeedDemoStoryIfNeeded() }
                #endif
                // Generous bottom padding so the Regenerate button can scroll
                // clear of the translucent tab bar even on shorter devices.
                .padding(.bottom, 100)
            }
            .background(Theme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("tab.story")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("nav.settings"))
                }
            }
            .sheet(item: $tappedWord) { word in
                WordDetailModal(word: word)
                    .presentationDetents([.medium])
            }
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "wordstory",
                   let last = url.pathComponents.last,
                   let id = UUID(uuidString: last),
                   let word = generatedFor.first(where: { $0.id == id }) {
                    tappedWord = word
                    return .handled
                }
                return .systemAction
            })
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Theme.ink.opacity(0.92))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .padding(.bottom, 90)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Selector

    private var selectorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("story.select.label")
            if allWords.isEmpty {
                Text("story.select.empty")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkQuiet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 12)
                    .background(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.rule, lineWidth: 1)
                    )
            } else {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(allWords.sorted(by: { $0.addedDate > $1.addedDate })) { word in
                        chipButton(for: word)
                    }
                }
                .padding(12)
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.rule, lineWidth: 1)
                )

                HStack(spacing: 14) {
                    Button {
                        for w in allWords where !w.learned { selectedIDs.insert(w.id) }
                    } label: {
                        Text("story.select.all_unlearned")
                            .font(.footnote)
                    }
                    Button {
                        selectedIDs.removeAll()
                    } label: {
                        Text("story.select.clear")
                            .font(.footnote)
                    }
                    Spacer()
                    Text("story.select.count \(selectedIDs.count)")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkQuiet)
                }
                .padding(.top, 2)
            }
        }
    }

    private func chipButton(for word: Word) -> some View {
        let isSelected = selectedIDs.contains(word.id)
        return Button {
            if isSelected { selectedIDs.remove(word.id) }
            else { selectedIDs.insert(word.id) }
        } label: {
            Text(word.sourceText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Theme.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Theme.paperSoft)
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor : Theme.rule, lineWidth: 1)
                )
                .opacity(word.learned ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Style picker

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("story.style.label")
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 145), spacing: 8)
            ], spacing: 8) {
                ForEach(StoryStyle.allCases) { s in
                    styleCard(for: s)
                }
            }
        }
    }

    private func styleCard(for s: StoryStyle) -> some View {
        let isSelected = style == s
        return Button {
            style = s
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: s.titleKey))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(String(localized: s.descriptionKey))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.accentBG : Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Theme.rule, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var customPromptField: some View {
        TextField("story.custom.placeholder", text: $customPrompt, axis: .vertical)
            .lineLimit(2...4)
            .padding(12)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.rule, lineWidth: 1)
            )
    }

    // MARK: - Generate

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack {
                if isGenerating { ProgressView().tint(.white) }
                Text(isGenerating ? "story.generating" : "story.generate")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canGenerate ? Color.accentColor : Theme.rule)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate || isGenerating)
    }

    private var canGenerate: Bool {
        !selectedIDs.isEmpty
        && (style != .custom || !customPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func errorBanner(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.danger)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Story output

    private func storyOutput(generated: APIService.GenerateResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Show / Hide Chinese button. When sentences[] is present, the
            // Chinese line interleaves directly under each English sentence.
            // When it's missing (older / truncated responses), we fall back
            // to rendering the two flat story_* strings as separate blocks.
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

            // Prefer the API-provided sentence pairs; if the response came
            // back without them (newer dual-language path can return an
            // empty `sentences` array on truncation), best-effort split
            // story_en + story_zh client-side. Only fall back to the
            // English-only flat block if we still can't pair them.
            let effective = effectiveSentences(generated: generated)
            if !effective.isEmpty {
                interleavedSentences(effective)
            } else {
                fallbackBlocks(generated: generated)
            }

            HStack(spacing: 16) {
                Text("story.meta.count \(generatedFor.count)")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkQuiet)
                Spacer()
                Button {
                    toggleSave()
                } label: {
                    Label(
                        isCurrentStorySaved ? "saved.save_button" : "saved.save_button",
                        systemImage: isCurrentStorySaved ? "heart.fill" : "heart"
                    )
                    .font(.footnote)
                    .foregroundStyle(isCurrentStorySaved ? Color.accentColor : Theme.inkSoft)
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel(Text("saved.save_button"))
                Button {
                    Task { await generate() }
                } label: {
                    Label("story.regenerate", systemImage: "arrow.clockwise")
                        .font(.footnote)
                }
                .disabled(isGenerating)
            }
        }
        .padding(20)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.rule, lineWidth: 1)
        )
    }

    /// Primary path: each sentence is its own block — English on top, optional
    /// Chinese translation directly below. Both sides get vocab highlighting
    /// using the same UUID-link scheme so taps open the same detail modal.
    private func interleavedSentences(_ sentences: [APIService.GenerateResponse.SentencePair]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: showChinese ? 3 : 0) {
                    Text(makeAttributedStory(text: pair.en, words: generatedFor))
                        .font(Theme.serif(18))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    if showChinese {
                        Text(makeChineseAttributed(
                            text: pair.zh,
                            words: generatedFor,
                            spans: pair.vocab_spans
                        ))
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.inkSoft)
                            .textSelection(.enabled)
                            .accessibilityLabel(Text(String(localized: "story.aria.chinese_for \(pair.en)")))
                    }
                }
            }
        }
    }

    /// Fallback when sentences[] is missing — old API responses or truncation.
    /// Same English-on-top semantics; the Chinese version goes below as a
    /// single block instead of being interleaved sentence-by-sentence.
    private func fallbackBlocks(generated: APIService.GenerateResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(makeAttributedStory(text: generated.story_en, words: generatedFor))
                .font(Theme.serif(18))
                .lineSpacing(8)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
            if showChinese, !generated.story_zh.isEmpty {
                Text(makeChineseAttributed(text: generated.story_zh, words: generatedFor))
                    .font(.system(size: 14))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.inkSoft)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Chinese highlight

    /// Highlight Chinese vocab translations as substrings of `text`.
    /// Prefers Gemini's per-sentence `vocab_spans` entry when present — that's
    /// the exact Chinese substring in this sentence's translation, so we
    /// don't risk highlighting unrelated dictionary candidates that happen to
    /// share characters. Falls back to dictionary-derived candidates (POS
    /// stripped, split on delimiters) when a span is missing. Longest
    /// candidates win when overlapping. Each highlight gets the same
    /// `wordstory://word/<UUID>` link attr as the English version, so taps
    /// route through the existing OpenURLAction.
    private func makeChineseAttributed(
        text: String,
        words: [Word],
        spans: [String: String]? = nil
    ) -> AttributedString {
        var attr = AttributedString(text)
        let nsText = text as NSString
        // Build (candidate, word) tuples, sorted longest-first so a
        // multi-character match wins over a single shared char.
        var lookups: [(candidate: String, word: Word)] = []
        for word in words {
            let key = word.sourceText.trimmingCharacters(in: .whitespaces).lowercased()
            if let span = spans?[key],
               !span.trimmingCharacters(in: .whitespaces).isEmpty {
                // Trust Gemini's exact span — don't pile on dictionary
                // candidates for this word so we avoid double-highlighting
                // a near-synonym elsewhere in the same sentence.
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

    /// Pull short Chinese segments out of a word's ECDICT/Gemini definition.
    /// Strips POS markers, splits on common delimiters, drops segments longer
    /// than 8 chars (those rarely appear verbatim in narrative prose).
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
                // Keep only short, CJK-bearing segments. 1–8 chars covers
                // most single-character translations and 2–4 char idioms;
                // longer segments are almost always explanatory phrases
                // that won't appear verbatim in narrative.
                guard (1...8).contains(s.count), containsCJK(s) else { continue }
                out.insert(s)
            }
        }
        return Array(out)
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.inkQuiet)
            .textCase(.uppercase)
    }

    // MARK: - AttributedString highlight

    private func makeAttributedStory(text: String, words: [Word]) -> AttributedString {
        var attr = AttributedString(text)
        let nsText = text as NSString

        // Longest-first so "self-esteem" beats "self".
        let sorted = words.sorted { $0.sourceText.count > $1.sourceText.count }
        // Track ranges already covered so shorter words don't re-wrap inside them.
        var coveredRanges: [NSRange] = []

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
                if coveredRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
                coveredRanges.append(match.range)
                guard let range = Range<AttributedString.Index>(match.range, in: attr) else { continue }
                attr[range].foregroundColor = .accentColor
                attr[range].underlineStyle = .single
                attr[range].link = URL(string: "wordstory://word/\(word.id.uuidString)")
            }
        }
        return attr
    }

    private func containsCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            (0x3400...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    // MARK: - Save / unsave

    /// Stable identity string used as the SavedStory match key.
    /// Prefers a JSON-encoded sentence-pair array (round-trippable) when
    /// the API gave us one. Falls back to a `flat:<en>|<zh>` tag for
    /// responses that came back without a `sentences` array — without
    /// the fallback, the save heart silently no-ops on those stories.
    private var currentStoryIdentity: String? {
        guard let generated else { return nil }
        if let pairs = generated.sentences, !pairs.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(pairs),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
        }
        return "flat:" + generated.story_en + "|" + generated.story_zh
    }

    /// Sentence pairs the renderer should actually use. Prefer the API's
    /// `sentences` field; on empty, split `story_en` / `story_zh` on
    /// sentence punctuation and zip the halves. Best-effort — when the
    /// two halves have a different sentence count we pad with empty zh,
    /// so the English still renders correctly.
    private func effectiveSentences(generated: APIService.GenerateResponse) -> [APIService.GenerateResponse.SentencePair] {
        if let pairs = generated.sentences, !pairs.isEmpty { return pairs }
        let enParts = splitForRendering(generated.story_en, delimiters: ".!?")
        let zhParts = splitForRendering(generated.story_zh, delimiters: "。！？")
        guard !enParts.isEmpty else { return [] }
        return enParts.enumerated().map { idx, en in
            let zh = idx < zhParts.count ? zhParts[idx] : ""
            return APIService.GenerateResponse.SentencePair(en: en, zh: zh)
        }
    }

    /// Split a story body into sentences on the given delimiters, keeping
    /// the delimiter glued to the preceding sentence (so periods don't get
    /// lost from the rendered output).
    private func splitForRendering(_ text: String, delimiters: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var sentences: [String] = []
        var current = ""
        let delimSet = Set(delimiters)
        for ch in trimmed {
            current.append(ch)
            if delimSet.contains(ch) {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { sentences.append(s) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    private var isCurrentStorySaved: Bool {
        guard let id = currentStoryIdentity else { return false }
        return savedStories.contains { $0.sentencesJSON == id }
    }

    private func toggleSave() {
        guard let generated, let json = currentStoryIdentity else { return }
        if let existing = savedStories.first(where: { $0.sentencesJSON == json }) {
            modelContext.delete(existing)
            try? modelContext.save()
            showToast(String(localized: "saved.unsaved_toast"))
            return
        }
        let preview = String(generated.story_en.prefix(40))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let story = SavedStory(
            style: style,
            direction: direction,
            sentencesJSON: json,
            vocabIDs: generatedFor.map(\.id),
            titlePreview: preview,
            storyEnFull: generated.story_en,
            storyZhFull: generated.story_zh
        )
        modelContext.insert(story)
        try? modelContext.save()
        showToast(String(localized: "saved.saved_toast"))
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            toastMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toastMessage == message {
                withAnimation { toastMessage = nil }
            }
        }
    }

    #if DEBUG
    /// Hydrate the demo story written by `SeedDemo` so screenshots 4 + 5 can
    /// render without a live Gemini call.
    private func hydrateSeedDemoStoryIfNeeded() {
        guard SeedDemo.isActive, generated == nil else { return }
        guard let data = UserDefaults.standard.data(forKey: "seedDemo.story"),
              let resp = try? JSONDecoder().decode(APIService.GenerateResponse.self, from: data)
        else { return }
        let vocabKeys = UserDefaults.standard.stringArray(forKey: "seedDemo.storyVocab") ?? []
        let vocab = vocabKeys.compactMap { key in
            allWords.first { $0.sourceText == key }
        }
        generated = resp
        generatedFor = vocab
        selectedIDs = Set(vocab.map(\.id))
    }
    #endif

    // MARK: - Generation

    @MainActor
    private func generate() async {
        let vocab = allWords.filter { selectedIDs.contains($0.id) }
        guard !vocab.isEmpty else { return }
        if style == .custom && customPrompt.trimmingCharacters(in: .whitespaces).isEmpty { return }

        isGenerating = true
        errorMessage = nil
        generated = nil

        let texts = vocab.map(\.sourceText)
        let prompt = customPrompt
        let dir = direction
        let st = style

        do {
            let response = try await APIService.generateStory(
                words: texts,
                style: st,
                customPrompt: prompt,
                direction: dir
            )
            print(String(format: "[StoryView] generated: sentences=%d, en=%d chars, zh=%d chars",
                         response.sentences?.count ?? 0,
                         response.story_en.count,
                         response.story_zh.count))
            generated = response
            generatedFor = vocab
            // Default: English shown, Chinese hidden. The user reveals
            // sentence-level Chinese via the toggle when they want to
            // verify their understanding.
            showChinese = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "error.generic")
        }
        isGenerating = false
    }
}

#Preview {
    StoryView(showSettings: .constant(false))
        .modelContainer(for: Word.self, inMemory: true)
}
