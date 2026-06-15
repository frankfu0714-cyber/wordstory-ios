import SwiftUI
import SwiftData

enum WordSortOrder: String, CaseIterable, Identifiable {
    case recent, alpha, unlearned
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .recent:    return "sort.recent"
        case .alpha:     return "sort.alpha"
        case .unlearned: return "sort.unlearned"
        }
    }
}

struct WordsView: View {
    @Binding var showSettings: Bool
    @Query private var allWords: [Word]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var sortOrder: WordSortOrder = .recent
    @State private var showAddSheet = false

    private var filteredAndSorted: [Word] {
        var list = allWords
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.sourceText.lowercased().contains(q)
                || $0.definition.lowercased().contains(q)
                || $0.example.lowercased().contains(q)
            }
        }
        switch sortOrder {
        case .recent:
            list.sort { $0.addedDate > $1.addedDate }
        case .alpha:
            list.sort { $0.sourceText.localizedStandardCompare($1.sourceText) == .orderedAscending }
        case .unlearned:
            list.sort {
                if $0.learned != $1.learned { return !$0.learned && $1.learned }
                return $0.addedDate > $1.addedDate
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if allWords.isEmpty {
                    emptyState
                } else if filteredAndSorted.isEmpty {
                    noMatches
                } else {
                    List {
                        ForEach(filteredAndSorted) { word in
                            WordRow(
                                word: word,
                                onToggleLearned: { toggleLearned(word) },
                                onRetryFetch: {
                                    Task { @MainActor in await refetch(word) }
                                }
                            )
                                .listRowBackground(Theme.paper)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(word)
                                    } label: {
                                        Label("action.delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        toggleLearned(word)
                                    } label: {
                                        Label(
                                            word.learned ? "action.mark_unlearned" : "action.mark_learned",
                                            systemImage: word.learned ? "circle" : "checkmark.circle"
                                        )
                                    }
                                    .tint(Color.accentColor)
                                }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                    .refreshable { await refetchAllPending() }
                }
            }
            .searchable(text: $searchText, prompt: Text("search.placeholder"))
            .navigationTitle("tab.words")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(selection: $sortOrder) {
                            ForEach(WordSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        } label: {
                            Text("sort.title")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(Text("sort.title"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("action.add_word"))
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddWordSheet()
            }
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 38))
                .foregroundStyle(Theme.inkQuiet.opacity(0.5))
            Text("words.empty.title")
                .font(Theme.serif(20))
                .foregroundStyle(Theme.inkSoft)
            Text("words.empty.subtitle")
                .font(.body)
                .foregroundStyle(Theme.inkQuiet)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Theme.inkQuiet.opacity(0.6))
            Text("words.no_matches")
                .font(.body)
                .foregroundStyle(Theme.inkQuiet)
        }
    }

    // MARK: - Mutations

    private func toggleLearned(_ word: Word) {
        word.learned.toggle()
        try? modelContext.save()
    }

    private func delete(_ word: Word) {
        modelContext.delete(word)
        try? modelContext.save()
    }

    /// Re-fetches the definition for a single word. Called from the back-face
    /// retry button. Logs to console on failure.
    @MainActor
    private func refetch(_ word: Word) async {
        let id = word.id
        let text = word.sourceText
        let dir = word.direction
        do {
            let resp = try await APIService.defineWord(text, direction: dir)
            guard let w = findWord(byID: id) else { return }
            w.definition = resp.definition
            w.example = resp.example
            w.definitionFetchFailed = false
            try? modelContext.save()
        } catch {
            print("[WordsView] refetch '\(text)' failed: \(error.localizedDescription)")
            guard let w = findWord(byID: id) else { return }
            w.definitionFetchFailed = true
            try? modelContext.save()
        }
    }

    /// Pull-to-refresh handler. Re-fetches every word whose previous fetch
    /// failed AND every word whose definition is still empty (e.g. legacy
    /// rows from before the fail-flag existed). Concurrent; preserves
    /// per-row success/failure independently.
    @MainActor
    private func refetchAllPending() async {
        let pending = allWords
            .filter { $0.definitionFetchFailed || $0.definition.isEmpty }
            .map { (id: $0.id, text: $0.sourceText, dir: $0.direction) }
        guard !pending.isEmpty else { return }
        print("[WordsView] pull-to-refresh: re-fetching \(pending.count) word(s)")

        await withTaskGroup(of: (UUID, APIService.DefineResponse?).self) { group in
            for item in pending {
                group.addTask {
                    do {
                        let resp = try await APIService.defineWord(item.text, direction: item.dir)
                        return (item.id, resp)
                    } catch {
                        print("[WordsView] bulk refetch '\(item.text)' failed: \(error.localizedDescription)")
                        return (item.id, nil)
                    }
                }
            }
            for await (id, resp) in group {
                guard let w = findWord(byID: id) else { continue }
                if let resp {
                    w.definition = resp.definition
                    w.example = resp.example
                    w.definitionFetchFailed = false
                } else {
                    w.definitionFetchFailed = true
                }
            }
        }
        try? modelContext.save()
    }

    private func findWord(byID id: UUID) -> Word? {
        let descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

/// Flashcard-style row: shows only the word until tapped. Tapping flips the
/// card to reveal the definition + example. Five minutes after revealing,
/// the card auto-flips back so the user can keep self-testing. Tapping again
/// while revealed flips back immediately. Per-row state is in-memory only —
/// every fresh launch starts with all cards hidden.
private struct WordRow: View {
    let word: Word
    let onToggleLearned: () -> Void
    let onRetryFetch: () -> Void

    @State private var revealed = false
    @State private var hideTask: Task<Void, Never>?
    @State private var isRetrying = false

    private static let autoHideDelay: Duration = .seconds(300)

    var body: some View {
        ZStack {
            frontFace
                .opacity(revealed ? 0 : 1)
                .zIndex(revealed ? 0 : 1)
            backFace
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(revealed ? 1 : 0)
                .zIndex(revealed ? 1 : 0)
        }
        .rotation3DEffect(.degrees(revealed ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: revealed)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    // MARK: - Faces

    private var frontFace: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.sourceText)
                    .font(Theme.serif(24, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .strikethrough(word.learned, color: Theme.inkQuiet)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if word.learned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green.opacity(0.7))
                        .font(.system(size: 14))
                }
                if word.definitionFetchFailed {
                    // Purely informational on the front face; the tappable
                    // retry control lives on the back face so tapping here
                    // still flips the card normally.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange.opacity(0.85))
                        .font(.system(size: 13))
                        .accessibilityLabel(Text("words.fetch_failed"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .opacity(word.learned ? 0.6 : 1.0)
    }

    private var backFace: some View {
        // Only the definition. The example sentence is preserved in the data
        // model and still rendered in `WordDetailModal` from the Story tab —
        // the flashcard itself stays clean: front = word, back = meaning.
        // If the most recent fetch failed, swap the definition slot for an
        // inline retry button that doesn't conflict with the card-flip tap.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.sourceText)
                    .font(Theme.serif(17, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .strikethrough(word.learned, color: Theme.inkQuiet)
                    .lineLimit(2)
                Spacer()
                if word.learned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green.opacity(0.7))
                        .font(.system(size: 14))
                }
            }
            if !word.definition.isEmpty {
                Text(word.definition)
                    .font(Theme.serif(18))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(6)
            } else if word.definitionFetchFailed {
                retryRow
            } else {
                Text("detail.no_definition")
                    .font(.subheadline.italic())
                    .foregroundStyle(Theme.inkQuiet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .opacity(word.learned ? 0.6 : 1.0)
    }

    /// Inline retry control shown on the back face when the most recent
    /// fetch failed. Implemented as a Button so its tap is consumed first
    /// and doesn't bubble up to the parent's flip gesture.
    private var retryRow: some View {
        Button {
            guard !isRetrying else { return }
            isRetrying = true
            onRetryFetch()
            // Optimistic: clear the "retrying" flag once the model has had
            // a moment to flip back (the parent saves on the main actor
            // after the await completes). 1.5s is a small ceiling — the
            // user sees feedback even on instant successes.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                isRetrying = false
            }
        } label: {
            HStack(spacing: 8) {
                if isRetrying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange.opacity(0.85))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("words.fetch_failed")
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                    Text("action.retry_fetch")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkQuiet)
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.accentColor)
                    .font(.footnote)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flip control

    private func toggle() {
        if revealed {
            revealed = false
            hideTask?.cancel()
            hideTask = nil
        } else {
            revealed = true
            hideTask?.cancel()
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: Self.autoHideDelay)
                guard !Task.isCancelled else { return }
                revealed = false
            }
        }
    }
}

#Preview {
    WordsView(showSettings: .constant(false))
        .modelContainer(for: Word.self, inMemory: true)
}
