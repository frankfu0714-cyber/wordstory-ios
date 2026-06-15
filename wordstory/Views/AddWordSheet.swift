import SwiftUI
import SwiftData

struct AddWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("languageDirection") private var directionRaw = LanguageDirection.enToZh.rawValue
    private var direction: LanguageDirection {
        LanguageDirection(rawValue: directionRaw) ?? .enToZh
    }

    @State private var singleInput = ""
    @State private var pasteInput = ""
    @State private var showingPaste = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    @Query private var allWords: [Word]
    private var existingLowercased: Set<String> {
        Set(allWords.map { $0.sourceText.lowercased() })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "arrow.forward")
                            .foregroundStyle(Theme.inkQuiet)
                            .font(.caption)
                        Text(direction.targetDisplayName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Text("→")
                            .foregroundStyle(Color.accentColor)
                        Text(direction.nativeDisplayName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                    }
                } footer: {
                    Text("add.direction_hint")
                        .font(.caption)
                        .foregroundStyle(Theme.inkQuiet)
                }
                .listRowBackground(Theme.paper)

                Section("add.single.label") {
                    TextField("add.single.placeholder", text: $singleInput)
                        .focused($focused)
                        .submitLabel(.go)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await addAll() } }
                }
                .listRowBackground(Theme.paper)

                Section {
                    DisclosureGroup(isExpanded: $showingPaste) {
                        TextField("add.paste.placeholder",
                                  text: $pasteInput,
                                  axis: .vertical)
                            .lineLimit(3...8)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Text("add.paste.hint")
                            .font(.caption)
                            .foregroundStyle(Theme.inkQuiet)
                    } label: {
                        Text("add.paste.label")
                            .font(.subheadline)
                    }
                }
                .listRowBackground(Theme.paper)

                if let message = errorMessage {
                    Section {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                    }
                    .listRowBackground(Theme.paper)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("add.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button {
                            Task { await addAll() }
                        } label: {
                            Text("action.add").fontWeight(.semibold)
                        }
                        .disabled(currentWords.isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
            .interactiveDismissDisabled(isWorking)
        }
    }

    // MARK: - Logic

    private var currentWords: [String] {
        if showingPaste && !pasteInput.isEmpty {
            let parts = pasteInput.split(whereSeparator: { c in
                c.isNewline || c == "," || c == "，" || c == "、" || c == ";" || c == "；"
            })
            return parts.map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let one = singleInput.trimmingCharacters(in: .whitespaces)
        return one.isEmpty ? [] : [one]
    }

    @MainActor
    private func addAll() async {
        let inputs = currentWords
        guard !inputs.isEmpty else { return }
        isWorking = true
        errorMessage = nil

        let existing = existingLowercased
        let unique = inputs.filter { !existing.contains($0.lowercased()) }
        guard !unique.isEmpty else {
            errorMessage = String(localized: "add.error.duplicates_only")
            isWorking = false
            return
        }

        // Insert empty records up front, capture their stable ids.
        var pending: [(id: UUID, text: String)] = []
        for text in unique {
            let w = Word(sourceText: text, direction: direction)
            modelContext.insert(w)
            pending.append((id: w.id, text: text))
        }
        try? modelContext.save()

        // Fetch definitions concurrently OFF the main actor — only the
        // (id, text) tuples cross the boundary, never the @Model instances.
        // Errors are logged in the child task (so they show up in Xcode
        // console) and surface to the UI via the `definitionFetchFailed`
        // flag below — no more silent `try?` swallowing.
        let dir = direction
        let results: [(UUID, APIService.DefineResponse?)] = await withTaskGroup(
            of: (UUID, APIService.DefineResponse?).self
        ) { group in
            for (id, text) in pending {
                group.addTask {
                    do {
                        let resp = try await APIService.defineWord(text, direction: dir)
                        return (id, resp)
                    } catch {
                        print("[AddWordSheet] define '\(text)' failed: \(error.localizedDescription)")
                        return (id, nil)
                    }
                }
            }
            var out: [(UUID, APIService.DefineResponse?)] = []
            for await item in group { out.append(item) }
            return out
        }

        // Back on the main actor: look each model up by id and fill in.
        for (id, resp) in results {
            guard let word = findWord(byID: id) else { continue }
            if let resp {
                word.definition = resp.definition
                word.example = resp.example
                word.definitionFetchFailed = false
            } else {
                word.definitionFetchFailed = true
            }
        }
        try? modelContext.save()

        isWorking = false
        singleInput = ""
        pasteInput = ""
        dismiss()
    }

    private func findWord(byID id: UUID) -> Word? {
        let descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

#Preview {
    AddWordSheet()
        .modelContainer(for: Word.self, inMemory: true)
}
