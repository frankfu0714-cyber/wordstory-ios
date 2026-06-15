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
    @AppStorage("languageDirection") private var directionRaw = LanguageDirection.enToZh.rawValue
    private var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
    }

    @State private var selectedIDs: Set<UUID> = []
    @State private var style: StoryStyle = .shortStory
    @State private var customPrompt = ""

    @State private var generatedText: String?
    @State private var generatedFor: [Word] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?

    @State private var tappedWord: Word?

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
                    if let text = generatedText {
                        storyOutput(text: text)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
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

    private func storyOutput(text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(makeAttributedStory(text: text, words: generatedFor))
                .font(Theme.serif(18))
                .lineSpacing(8)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)

            HStack {
                Text("story.meta.count \(generatedFor.count)")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkQuiet)
                Spacer()
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

    // MARK: - Generation

    @MainActor
    private func generate() async {
        let vocab = allWords.filter { selectedIDs.contains($0.id) }
        guard !vocab.isEmpty else { return }
        if style == .custom && customPrompt.trimmingCharacters(in: .whitespaces).isEmpty { return }

        isGenerating = true
        errorMessage = nil
        generatedText = nil

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
            generatedText = response.story
            generatedFor = vocab
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
