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
    @AppStorage("languageDirection") private var directionRaw = LanguageDirection.enToZh.rawValue
    private var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
    }

    @State private var sortOrder: WordSortOrder = .recent
    @State private var showAddSheet = false

    // ---- type-to-add bar state ----
    @State private var addText = ""
    @State private var isAdding = false
    @State private var flashedWordID: UUID?
    @State private var pendingScrollID: UUID?
    @State private var toastMessage: String?
    @FocusState private var addFieldFocused: Bool

    // ---- autocomplete suggestions ----
    @State private var suggestions: [String] = []
    @State private var suggestionsTask: Task<Void, Never>?

    private var sortedWords: [Word] {
        var list = allWords
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
            ZStack(alignment: .bottom) {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    typeToAddBar
                        .onChange(of: addText) { _, newValue in
                            updateSuggestions(for: newValue)
                        }
                    if !suggestions.isEmpty && !addText.isEmpty {
                        suggestionsList
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if allWords.isEmpty {
                        emptyState
                    } else {
                        ScrollViewReader { proxy in
                            List {
                                ForEach(sortedWords) { word in
                                    WordRow(
                                        word: word,
                                        isFlashed: flashedWordID == word.id,
                                        onToggleLearned: { toggleLearned(word) },
                                        onRetryFetch: {
                                            Task { @MainActor in await refetch(word) }
                                        }
                                    )
                                        .id(word.id)
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
                            .onChange(of: pendingScrollID) { _, newValue in
                                if let newValue {
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        proxy.scrollTo(newValue, anchor: .center)
                                    }
                                    pendingScrollID = nil
                                }
                            }
                        }
                    }
                }
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

    // MARK: - Type-to-add bar

    /// Repurposed from the previous search field: now Enter on this field
    /// triggers a fresh definition fetch + insert. The bulk-paste "+" button
    /// in the nav bar is the other path for adding many at once.
    private var typeToAddBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .foregroundStyle(Theme.inkQuiet)
                .font(.system(size: 16))
            TextField("add_field.placeholder", text: $addText)
                .focused($addFieldFocused)
                .submitLabel(.done)
                .onSubmit { Task { @MainActor in await submitAdd() } }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(isAdding)
            if isAdding {
                ProgressView()
                    .controlSize(.small)
            } else if !addText.isEmpty {
                Button {
                    addText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkQuiet.opacity(0.6))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.rule, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// Autocomplete dropdown rendered directly under `typeToAddBar`.
    /// Bounded to 280pt so a wide prefix match (e.g. "a") doesn't push the
    /// word list off-screen — the inner `ScrollView` handles overflow.
    private var suggestionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { index, word in
                    Button {
                        selectSuggestion(word)
                    } label: {
                        HStack {
                            Text(word)
                                .font(Theme.serif(16))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < suggestions.count - 1 {
                        Divider().opacity(0.45)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.rule, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Empty state

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Type-to-add submit / flash / toast

    /// Called when the user hits Enter in the type-to-add bar.
    /// - Trims whitespace.
    /// - Case-insensitively checks for an existing word; if found, flashes
    ///   that row, scrolls to it, shows the duplicate toast, and exits.
    /// - Otherwise inserts an empty Word into SwiftData (so the row appears
    ///   immediately at the top), kicks off the definition fetch, and back-
    ///   fills success or marks `definitionFetchFailed = true`.
    /// `overrideText` lets the autocomplete dropdown submit a specific word
    /// without round-tripping through the bound `addText` state.
    @MainActor
    private func submitAdd(overrideText: String? = nil) async {
        let raw = overrideText ?? addText
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAdding else { return }

        // Duplicate check (case-insensitive on the source text).
        let lower = trimmed.lowercased()
        if let existing = allWords.first(where: { $0.sourceText.lowercased() == lower }) {
            addText = ""
            flash(existing.id)
            pendingScrollID = existing.id
            showToast(String(localized: "add_field.duplicate_toast"))
            return
        }

        isAdding = true
        let word = Word(sourceText: trimmed, direction: direction)
        modelContext.insert(word)
        try? modelContext.save()
        let id = word.id
        let dir = direction
        addText = ""
        // Hand focus back so the user can keep typing rapid-fire if they want.
        addFieldFocused = true

        do {
            let resp = try await APIService.defineWord(trimmed, direction: dir)
            if let w = findWord(byID: id) {
                w.definition = resp.definition
                w.example = resp.example
                w.definitionFetchFailed = false
            }
        } catch {
            print("[WordsView] type-to-add '\(trimmed)' failed: \(error.localizedDescription)")
            if let w = findWord(byID: id) {
                w.definitionFetchFailed = true
            }
        }
        try? modelContext.save()
        isAdding = false
    }

    /// Debounce keystrokes by 100ms then query the local dictionary for
    /// prefix matches. Cancels any in-flight query when called again so
    /// rapid typing doesn't race.
    private func updateSuggestions(for text: String) {
        suggestionsTask?.cancel()
        let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.isEmpty {
            suggestions = []
            return
        }
        suggestionsTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let results = await DictionaryService.shared.searchPrefix(prefix, limit: 20)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                suggestions = results
            }
        }
    }

    /// Tap handler for an autocomplete row — submits that exact word as
    /// if the user had typed it and hit Enter, then closes the dropdown.
    private func selectSuggestion(_ word: String) {
        suggestionsTask?.cancel()
        suggestionsTask = nil
        // Hide the dropdown immediately so it doesn't linger during the
        // async fetch — the submitAdd flow will clear addText on completion
        // which would also trigger an empty-suggestions onChange, but doing
        // it eagerly here gives instant visual feedback.
        withAnimation(.easeInOut(duration: 0.15)) {
            suggestions = []
        }
        Task { @MainActor in await submitAdd(overrideText: word) }
    }

    /// Briefly highlight a row (used when typing an already-present word).
    private func flash(_ id: UUID) {
        flashedWordID = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            if flashedWordID == id { flashedWordID = nil }
        }
    }

    /// Show a small bottom toast that auto-dismisses after ~2s.
    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toastMessage == message { toastMessage = nil }
        }
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
    let isFlashed: Bool
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
        // Subtle yellow flash when the user types a word that's already in
        // the list — see WordsView.flash(_:).
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(isFlashed ? 0.22 : 0))
                .padding(.horizontal, -10)
                .padding(.vertical, -4)
                .animation(.easeInOut(duration: 0.35), value: isFlashed)
        )
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
        // Speaker button overlay — Button gets first crack at the tap so the
        // flip gesture below never fires inside its hit area.
        .overlay(alignment: .topTrailing) {
            Button {
                Task { @MainActor in
                    SpeechService.shared.speak(
                        word.sourceText,
                        language: word.direction.sourceLanguageCode
                    )
                }
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel(Text("speech.button.aria"))
            .padding(.trailing, 6)
            .padding(.top, 2)
        }
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

/// Small scale + opacity pulse on press — used by the speaker buttons.
/// Lives at file scope so both `WordRow` and any other call site (e.g.
/// `WordDetailModal`) can share the same feel.
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

#Preview {
    WordsView(showSettings: .constant(false))
        .modelContainer(for: Word.self, inMemory: true)
}
