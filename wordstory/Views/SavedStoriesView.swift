import SwiftUI
import SwiftData

struct SavedStoriesView: View {
    @Binding var showSettings: Bool
    @Query(sort: \SavedStory.dateCreated, order: .reverse) private var stories: [SavedStory]
    @Environment(\.modelContext) private var modelContext
    @Query private var allWords: [Word]
    /// See StoryView for rationale — explicit-locale resolve to keep the
    /// nav title in sync with same-session Settings switches.
    @Environment(\.locale) private var locale

    /// Drives the title-edit sheet via `.sheet(item:)`. nil = sheet closed.
    @State private var editingStory: SavedStory?
    /// Brief bottom toast (e.g. "Generating a new variation…" after the
    /// regenerate action fires). Same shape as the toast in `WordsView`.
    @State private var toastMessage: String?

    /// In-progress generations sort to the top so the user sees them while
    /// the background Task is still running; everything else falls back to
    /// reverse-chron.
    private var sortedStories: [SavedStory] {
        stories.sorted { a, b in
            if a.isGenerating != b.isGenerating { return a.isGenerating && !b.isGenerating }
            return a.dateCreated > b.dateCreated
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if stories.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sortedStories) { story in
                            NavigationLink {
                                SavedStoryDetail(story: story) {
                                    regenerate(story)
                                }
                            } label: {
                                row(for: story)
                            }
                            .listRowBackground(Theme.paper)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(story)
                                } label: {
                                    Label("action.delete", systemImage: "trash")
                                }
                            }
                            // Leading swipe → rename. Gated on completed
                            // stories: generating + failed rows don't have
                            // any content to title yet, and the same
                            // gating is mirrored on the detail-view pencil.
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if !story.isGenerating && !story.generationFailed {
                                    Button {
                                        editingStory = story
                                    } label: {
                                        Label("saved.swipe.edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                            // Long-press → regenerate. Gated to completed
                            // stories: an in-flight or failed source has no
                            // useful vocab provenance to copy.
                            .contextMenu {
                                if !story.isGenerating && !story.generationFailed {
                                    Button {
                                        regenerate(story)
                                    } label: {
                                        Label("saved.regenerate", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(String(localized: "saved.tab", locale: locale))
            .navigationBarTitleDisplayMode(.large)
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
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: toastMessage)
            .sheet(item: $editingStory) { story in
                TitleEditSheet(story: story)
            }
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
        }
    }

    @ViewBuilder
    private func row(for story: SavedStory) -> some View {
        if story.isGenerating {
            generatingRow(for: story)
        } else if story.generationFailed {
            failedRow(for: story)
        } else {
            completedRow(for: story)
        }
    }

    private func completedRow(for story: SavedStory) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // displayTitle: user-set customTitle when present, else the
            // auto-derived titlePreview. Suffix-ellipsis only on the auto
            // form so user-set titles render exactly as typed.
            Text(displayLabel(for: story))
                .font(Theme.serif(16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            chipsRow(for: story)
        }
        .padding(.vertical, 4)
    }

    private func displayLabel(for story: SavedStory) -> String {
        if let custom = story.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return story.titlePreview.isEmpty ? "—" : story.titlePreview + "…"
    }

    private func generatingRow(for story: SavedStory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.accentColor)
                Text("saved.generating")
                    .font(Theme.serif(16, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
            }
            let words = vocabPreview(for: story)
            if !words.isEmpty {
                Text(words)
                    .font(.caption)
                    .foregroundStyle(Theme.inkQuiet)
                    .lineLimit(2)
            }
            chipsRow(for: story)
        }
        .padding(.vertical, 4)
    }

    private func failedRow(for story: SavedStory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                    .font(.system(size: 14))
                Text("saved.failed")
                    .font(Theme.serif(16, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                Spacer()
                Button {
                    retry(story)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("saved.retry")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }
            if let reason = story.generationFailureReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Theme.inkQuiet)
                    .lineLimit(2)
            }
            chipsRow(for: story)
        }
        .padding(.vertical, 4)
    }

    private func chipsRow(for story: SavedStory) -> some View {
        HStack(spacing: 6) {
            Text(LocalizedStringKey(story.style.titleKeyString))
                .font(.caption2)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.accentColor.opacity(0.10))
                )
                .foregroundStyle(Color.accentColor)
            Text(directionLabel(for: story.direction))
                .font(.caption2)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Theme.paperSoft)
                )
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(story.dateCreated, format: .dateTime.month(.abbreviated).day().year())
                .font(.caption2)
                .foregroundStyle(Theme.inkQuiet)
        }
    }

    private func directionLabel(for d: LanguageDirection) -> String {
        "\(d.targetDisplayName) → \(d.nativeDisplayName)"
    }

    private func vocabPreview(for story: SavedStory) -> String {
        let ids = Set(story.vocabIDs)
        let words = allWords.filter { ids.contains($0.id) }.prefix(6).map(\.sourceText)
        return words.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 38))
                .foregroundStyle(Theme.inkQuiet.opacity(0.5))
            Text("saved.empty_state")
                .font(.body)
                .foregroundStyle(Theme.inkQuiet)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(_ story: SavedStory) {
        modelContext.delete(story)
        try? modelContext.save()
    }

    /// Spawns a brand-new generation against the same vocab/style/direction
    /// as `source`. Used for spaced repetition: the user reads variation A,
    /// then taps Regenerate to get variation B over the same words. Inserts
    /// the placeholder immediately (so the user sees a "Generating…" row at
    /// the top of the list) and fires `runGeneration` in the background.
    /// The original `source` is left untouched.
    private func regenerate(_ source: SavedStory) {
        let ids = Set(source.vocabIDs)
        let texts = allWords.filter { ids.contains($0.id) }.map(\.sourceText)
        guard !texts.isEmpty else {
            showToast(String(localized: "saved.regenerate.no_vocab"))
            return
        }

        let placeholder = SavedStory(
            style: source.style,
            direction: source.direction,
            vocabIDs: source.vocabIDs,
            customPromptStored: source.customPromptStored,
            isGenerating: true
        )
        modelContext.insert(placeholder)
        try? modelContext.save()

        showToast(String(localized: "saved.regenerate.toast"))

        let id = placeholder.id
        let st = source.style
        let dir = source.direction
        let prompt = source.customPromptStored
        let ctx = modelContext

        Task { @MainActor in
            await runGeneration(
                id: id,
                texts: texts,
                style: st,
                customPrompt: prompt,
                direction: dir,
                context: ctx
            )
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toastMessage == message { toastMessage = nil }
        }
    }

    /// Reset a failed row to in-flight and re-dispatch the same generation
    /// request. Original style / direction / vocabIDs / customPrompt all
    /// come from the stored SavedStory so the retry hits the same intent.
    private func retry(_ story: SavedStory) {
        let texts: [String] = {
            let ids = Set(story.vocabIDs)
            return allWords.filter { ids.contains($0.id) }.map(\.sourceText)
        }()
        guard !texts.isEmpty else { return }
        story.isGenerating = true
        story.generationFailed = false
        story.generationFailureReason = nil
        try? modelContext.save()

        let id = story.id
        let st = story.style
        let dir = story.direction
        let prompt = story.customPromptStored
        let ctx = modelContext

        Task { @MainActor in
            await runGeneration(
                id: id,
                texts: texts,
                style: st,
                customPrompt: prompt,
                direction: dir,
                context: ctx
            )
        }
    }
}

#Preview {
    SavedStoriesView(showSettings: .constant(false))
        .modelContainer(for: [Word.self, SavedStory.self], inMemory: true)
}
