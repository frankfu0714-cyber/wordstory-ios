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
                }
                .listRowBackground(Theme.paper)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("saved.title.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("saved.title.done") { commit() }
                        .fontWeight(.semibold)
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
