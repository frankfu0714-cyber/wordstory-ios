import SwiftUI
import SwiftData

/// Story-composer screen pre-filled from a saved story so the user can
/// tweak vocab / style / custom prompt before re-firing the generator.
/// Pushed into the host's existing NavigationStack (Saved tab) — no
/// NavigationStack of its own.
///
/// State is seeded once in `init` from the source `SavedStory` and then
/// owned locally; the user's adjustments here don't write back to the
/// original. Once Generate fires, the new placeholder lands in the Saved
/// tab via `StoryComposerForm.startGeneration`, and `onGenerated` pops
/// this screen so the user is back on the list to watch it stream in.
struct RegenerateStoryView: View {
    let source: SavedStory
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<UUID>
    @State private var style: StoryStyle
    @State private var customPrompt: String

    init(source: SavedStory) {
        self.source = source
        _selectedIDs = State(initialValue: Set(source.vocabIDs))
        _style = State(initialValue: source.style)
        _customPrompt = State(initialValue: source.customPromptStored)
    }

    var body: some View {
        StoryComposerForm(
            selectedIDs: $selectedIDs,
            style: $style,
            customPrompt: $customPrompt,
            onGenerated: { dismiss() }
        )
        .navigationTitle("regenerate.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
