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
                                SavedStoryDetail(story: story)
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
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(String(localized: "saved.tab", locale: locale))
            .navigationBarTitleDisplayMode(.large)
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
