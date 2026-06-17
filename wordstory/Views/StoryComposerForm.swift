import SwiftUI
import SwiftData

/// Shared form for picking words + style + (optionally) a custom prompt and
/// dispatching the generate API call. Lives behind two entry points:
///
/// - `StoryView` — tab-rooted, fresh empty state.
/// - `RegenerateStoryView` — pushed from a `SavedStory`, seeded with that
///   story's vocab / style / custom prompt so the user can tweak before
///   firing the next generation.
///
/// State is owned by the host (via bindings) so both entry points can wire
/// the same StoryComposerForm into different navigation contexts without
/// duplicating the chip/style/generate UI.
struct StoryComposerForm: View {
    @Query private var allWords: [Word]
    @Environment(\.modelContext) private var modelContext

    @Binding var selectedIDs: Set<UUID>
    @Binding var style: StoryStyle
    @Binding var customPrompt: String
    @Binding var length: StoryLength

    /// Called immediately after the placeholder `SavedStory` is inserted +
    /// the background generation task is dispatched. The Story tab leaves
    /// this nil (the user stays on the form to kick off more); the
    /// regenerate path uses it to pop back to the saved-stories list.
    var onGenerated: (() -> Void)? = nil

    @State private var toastMessage: String?

    // App is English-learner only as of this release; the user-facing
    // direction toggle is gone and every generation is en-to-zh. Per-Word
    // `direction` storage is preserved so legacy zh-to-en cards still
    // display correctly, but new flow hard-codes here.
    private let direction: LanguageDirection = .enToZh

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                selectorSection
                styleSection
                lengthSection
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

    // MARK: - Length picker

    /// Segmented Standard/Brief picker. Standard preserves the per-style
    /// word target (~150 words). Brief overrides it with a ~40–60 word
    /// ceiling so the user can avoid padded output when only a few vocab
    /// words are selected.
    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("length.label")
            HStack(spacing: 8) {
                ForEach(StoryLength.allCases) { l in
                    lengthCard(for: l)
                }
            }
        }
    }

    private func lengthCard(for l: StoryLength) -> some View {
        let isSelected = length == l
        return Button {
            length = l
        } label: {
            Text(LocalizedStringKey(l.titleKeyString))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Theme.paper)
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor : Theme.rule, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var customPromptField: some View {
        TextField("story.custom.placeholder", text: $customPrompt, axis: .vertical)
            .lineLimit(2...4)
            .foregroundStyle(Theme.ink)
            .tint(Color.accentColor)
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
    /// background. The Story tab can immediately keep tweaking and kick off
    /// another generation in parallel — each lands as its own row in the
    /// Saved tab. The regenerate flow calls `onGenerated` to pop the form
    /// off the nav stack once the dispatch has been kicked off.
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
            length: length,
            isGenerating: true
        )
        modelContext.insert(placeholder)
        try? modelContext.save()

        showToast(String(localized: "story.toast.generating"))

        let texts = vocab.map(\.sourceText)
        let st = style
        let dir = direction
        let len = length
        let id = placeholder.id
        let ctx = modelContext

        Task { @MainActor in
            await runGeneration(
                id: id,
                texts: texts,
                style: st,
                customPrompt: promptValue,
                direction: dir,
                length: len,
                context: ctx
            )
        }

        onGenerated?()
    }
}
