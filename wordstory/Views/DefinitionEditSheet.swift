import SwiftUI
import SwiftData

/// Lets the user override the ECDICT/API Chinese meaning for a word.
/// Mirrors `TitleEditSheet`'s shape: a small detent sheet with cancel +
/// save, plus a "Reset to dictionary" affordance that clears the override
/// so the original definition takes over again.
///
/// Writes go to `Word.customDefinition`. Trimmed-empty saves clear the
/// override (same semantics as the explicit Reset button).
struct DefinitionEditSheet: View {
    let word: Word
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var draft: String
    @FocusState private var fieldFocused: Bool

    init(word: Word) {
        self.word = word
        let initial = word.customDefinition ?? word.definition
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("definition.edit.placeholder", text: $draft, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($fieldFocused)
                        // Pin typed text + cursor tint to brand inks —
                        // default `.label` renders near-white on cream in
                        // dark-system-mode and disappears.
                        .foregroundStyle(Theme.ink)
                        .tint(Color.accentColor)
                }
                .listRowBackground(Theme.paper)

                if !word.definition.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("definition.edit.dictionary_label")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkQuiet)
                                .textCase(.uppercase)
                                .tracking(1.0)
                            Text(word.definition)
                                .font(Theme.serif(15))
                                .foregroundStyle(Theme.inkSoft)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(Theme.paper)
                }

                if word.hasCustomDefinition {
                    Section {
                        Button(role: .destructive) {
                            resetToDictionary()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.uturn.backward")
                                Text("definition.edit.reset")
                            }
                        }
                    }
                    .listRowBackground(Theme.paper)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("definition.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Explicit accent + semibold so Cancel stays readable
                    // on cream; default tint goes near-pastel pink here.
                    Button("action.cancel") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Primary action — filled accent capsule. Mirrors the
                    // treatment on `TitleEditSheet.Done`.
                    Button {
                        commit()
                    } label: {
                        Text("definition.edit.save")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear { fieldFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        word.customDefinition = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
        dismiss()
    }

    private func resetToDictionary() {
        word.customDefinition = nil
        try? modelContext.save()
        dismiss()
    }
}
