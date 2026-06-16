import SwiftUI
import SwiftData

/// A wrapping flow layout — used for the word chip selector and the
/// generating-placeholder chip rows in SavedStoryDetail.
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

/// Story generator. Hitting "Generate" inserts a placeholder `SavedStory`
/// (isGenerating=true) and fires the API call in the background — the user
/// can immediately tweak selection and kick off another generation in
/// parallel. Completed stories live in the Saved tab; this view never
/// renders the result inline.
struct StoryView: View {
    @Binding var showSettings: Bool
    @Query private var allWords: [Word]
    @Environment(\.modelContext) private var modelContext
    /// Read from `\.locale` so the nav title resolves against the user's
    /// choice without waiting for a relaunch. `WordstoryApp` installs the
    /// env locale from the `uiLanguage` AppStorage; LocalizedStringKey-based
    /// Text views pick it up directly, but `navigationTitle` on iOS 17/18
    /// bridges through UIKit and intermittently keeps the bundle-locale
    /// title. Resolving the title via the explicit Locale dodges that.
    @Environment(\.locale) private var locale

    // App is English-learner only as of this release; the user-facing
    // direction toggle is gone and every generation is en-to-zh. Per-Word
    // `direction` storage is preserved so legacy zh-to-en cards still
    // display correctly, but new flow hard-codes here.
    private let direction: LanguageDirection = .enToZh

    @State private var selectedIDs: Set<UUID> = []
    @State private var style: StoryStyle = .shortStory
    @State private var customPrompt = ""
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
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .background(Theme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: "tab.story", locale: locale))
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
                // LocalizedStringKey respects the SwiftUI `\.locale` env that
                // WordstoryApp installs from the user's uiLanguage preference;
                // String(localized:) reads Bundle.main, which only updates on
                // next launch, so picking 中文 in Settings used to leave these
                // cards in English until relaunch.
                Text(LocalizedStringKey(s.titleKeyString))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(LocalizedStringKey(s.descriptionKeyString))
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
            startGeneration()
        } label: {
            HStack {
                Text("story.generate")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canGenerate ? Color.accentColor : Theme.rule)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate)
    }

    private var canGenerate: Bool {
        !selectedIDs.isEmpty
        && (style != .custom || !customPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.inkQuiet)
            .textCase(.uppercase)
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

    // MARK: - Auto-save dispatch

    /// Inserts a placeholder `SavedStory` and fires the API call in the
    /// background. The user can immediately keep tweaking the selection
    /// and kick off another generation in parallel — each lands as its
    /// own row in the Saved tab.
    private func startGeneration() {
        guard canGenerate else { return }
        let vocab = allWords.filter { selectedIDs.contains($0.id) }
        guard !vocab.isEmpty else { return }

        let promptValue = customPrompt
        let placeholder = SavedStory(
            style: style,
            direction: direction,
            vocabIDs: vocab.map(\.id),
            customPromptStored: style == .custom ? promptValue : "",
            isGenerating: true
        )
        modelContext.insert(placeholder)
        try? modelContext.save()

        showToast(String(localized: "story.toast.generating"))

        let texts = vocab.map(\.sourceText)
        let st = style
        let dir = direction
        let id = placeholder.id
        let ctx = modelContext

        Task { @MainActor in
            await runGeneration(
                id: id,
                texts: texts,
                style: st,
                customPrompt: promptValue,
                direction: dir,
                context: ctx
            )
        }
    }
}

// MARK: - Background generation runner

@MainActor
func runGeneration(
    id: UUID,
    texts: [String],
    style: StoryStyle,
    customPrompt: String,
    direction: LanguageDirection,
    context: ModelContext
) async {
    let fd = FetchDescriptor<SavedStory>(predicate: #Predicate { $0.id == id })
    do {
        let response = try await APIService.generateStory(
            words: texts,
            style: style,
            customPrompt: customPrompt,
            direction: direction
        )
        print(String(format: "[StoryView] generated: sentences=%d, en=%d chars, zh=%d chars",
                     response.sentences?.count ?? 0,
                     response.story_en.count,
                     response.story_zh.count))
        guard let saved = try? context.fetch(fd).first else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(response.sentences ?? []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let preview = String(response.story_en.prefix(40))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        saved.sentencesJSON = json
        saved.titlePreview = preview
        saved.storyEnFull = response.story_en
        saved.storyZhFull = response.story_zh
        saved.isGenerating = false
        saved.generationFailed = false
        saved.generationFailureReason = nil
        try? context.save()
    } catch {
        guard let saved = try? context.fetch(fd).first else { return }
        saved.isGenerating = false
        saved.generationFailed = true
        saved.generationFailureReason = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        try? context.save()
    }
}

#Preview {
    StoryView(showSettings: .constant(false))
        .modelContainer(for: Word.self, inMemory: true)
}
