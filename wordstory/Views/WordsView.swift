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
                            WordRow(word: word, onToggleLearned: { toggleLearned(word) })
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
}

private struct WordRow: View {
    let word: Word
    let onToggleLearned: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.sourceText)
                    .font(Theme.serif(20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .strikethrough(word.learned, color: Theme.inkQuiet)
                    .lineLimit(2)
                Spacer()
                if word.learned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green.opacity(0.7))
                        .font(.system(size: 14))
                        .onTapGesture { onToggleLearned() }
                }
            }
            if !word.definition.isEmpty {
                Text(word.definition)
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(4)
            }
            if !word.example.isEmpty {
                Text(word.example)
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkQuiet)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.rule)
                            .frame(width: 2)
                    }
            }
        }
        .padding(.vertical, 4)
        .opacity(word.learned ? 0.6 : 1.0)
    }
}

#Preview {
    WordsView(showSettings: .constant(false))
        .modelContainer(for: Word.self, inMemory: true)
}
