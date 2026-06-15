import SwiftUI
import SwiftData

struct SavedStoriesView: View {
    @Binding var showSettings: Bool
    @Query(sort: \SavedStory.dateCreated, order: .reverse) private var stories: [SavedStory]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if stories.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(stories) { story in
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
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("saved.tab")
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
            }
        }
    }

    private func row(for story: SavedStory) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(story.titlePreview.isEmpty ? "—" : story.titlePreview + "…")
                .font(Theme.serif(16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(String(localized: story.style.titleKey))
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
        .padding(.vertical, 4)
    }

    private func directionLabel(for d: LanguageDirection) -> String {
        "\(d.targetDisplayName) → \(d.nativeDisplayName)"
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
}

#Preview {
    SavedStoriesView(showSettings: .constant(false))
        .modelContainer(for: [Word.self, SavedStory.self], inMemory: true)
}
