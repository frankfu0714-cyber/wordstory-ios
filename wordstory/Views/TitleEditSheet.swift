import SwiftUI
import SwiftData

/// Reusable bottom-detent sheet for renaming a `SavedStory`. Used both from
/// `SavedStoryDetail` (via toolbar pencil) and from the `SavedStoriesView`
/// list (via leading swipe action). Trimmed-empty commits reset
/// `customTitle` to nil so the auto preview takes over again.
struct TitleEditSheet: View {
    let story: SavedStory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var draft: String

    init(story: SavedStory) {
        self.story = story
        let initial = story.customTitle ?? story.titlePreview
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("saved.title.placeholder", text: $draft)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(commit)
                        // System TextField defaults to `.label`, which in
                        // dark-system-mode renders near-white and disappears
                        // against the cream sheet. Pin both the typed text
                        // and the cursor tint to the brand inks.
                        .foregroundStyle(Theme.ink)
                        .tint(Color.accentColor)
                }
                .listRowBackground(Theme.paper)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("saved.title.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Explicit accent + semibold so Cancel stays readable
                    // on cream; default tint renders a near-pastel pink
                    // against this background.
                    Button("action.cancel") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Primary action — filled accent capsule. Beats the
                    // pencil-pale default text button and makes the commit
                    // step unmistakable.
                    Button {
                        commit()
                    } label: {
                        Text("saved.title.done")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        story.customTitle = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
        dismiss()
    }
}
