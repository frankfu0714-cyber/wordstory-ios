import SwiftUI
import SwiftData

/// A wrapping flow layout — used for the word chip selector and the
/// generating-placeholder chip rows in SavedStoryDetail.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + rowSpacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowHeight + rowSpacing; rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Tab-rooted story generator. Wraps the shared `StoryComposerForm` in this
/// tab's NavigationStack + gear toolbar. The form itself owns the
/// selector / style picker / generate button — it's reused by the
/// regenerate-from-saved-story flow with seeded state.
struct StoryView: View {
    @Binding var showSettings: Bool

    @State private var selectedIDs: Set<UUID> = []
    @State private var style: StoryStyle = .shortStory
    @State private var customPrompt = ""
    @State private var length: StoryLength = .standard

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    pinnedTitle
                    StoryComposerForm(
                        selectedIDs: $selectedIDs,
                        style: $style,
                        customPrompt: $customPrompt,
                        length: $length
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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

    private var pinnedTitle: some View {
        Text("tab.story")
            .font(.system(.largeTitle, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

// MARK: - Background generation runner

@MainActor
func runGeneration(
    id: UUID,
    texts: [String],
    style: StoryStyle,
    customPrompt: String,
    direction: LanguageDirection,
    length: StoryLength = .standard,
    context: ModelContext
) async {
    let fd = FetchDescriptor<SavedStory>(predicate: #Predicate { $0.id == id })
    do {
        let response = try await APIService.generateStory(
            words: texts,
            style: style,
            customPrompt: customPrompt,
            direction: direction,
            length: length
        )
        print(String(format: "[StoryView] generated: sentences=%d, en=%d chars, zh=%d chars",
                     response.sentences?.count ?? 0,
                     response.story_en.count,
                     response.story_zh.count))
        guard let saved = try? context.fetch(fd).first else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(response.sentences ?? []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let preview = String(response.story_en.prefix(40))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        saved.sentencesJSON = json
        saved.titlePreview = preview
        saved.storyEnFull = response.story_en
        saved.storyZhFull = response.story_zh
        saved.isGenerating = false
        saved.generationFailed = false
        saved.generationFailureReason = nil
        try? context.save()
    } catch {
        guard let saved = try? context.fetch(fd).first else { return }
        saved.isGenerating = false
        saved.generationFailed = true
        saved.generationFailureReason = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        try? context.save()
    }
}

#Preview {
    StoryView(showSettings: .constant(false))
        .modelContainer(for: Word.self, inMemory: true)
}
