import SwiftUI

/// "Choose English word" picker shown when the user types a Chinese term in
/// the add bar. Words list stays English-only; Chinese is just a search
/// pivot, so tapping a Chinese suggestion opens this sheet rather than
/// adding a zh-fronted card directly.
struct EnglishSynonymsSheet: View {

    let chinese: String
    /// Called with the chosen English headword. Caller dismisses + runs
    /// the normal en-to-zh add flow.
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [DictionaryService.Candidate] = []
    @State private var isLoading = true

    private static let candidateLimit = 30

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                content
            }
            .navigationTitle("synonyms.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel(Text("synonyms.cancel"))
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.large)
                .tint(Color.accentColor)
        } else if candidates.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var subtitle: some View {
        // Use AttributedString to highlight the queried term in accent color.
        Text(String(format: String(localized: "synonyms.subtitle"), chinese))
            .font(Theme.serif(15))
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 10)
    }

    private var list: some View {
        VStack(spacing: 0) {
            subtitle
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(candidates, id: \.english) { candidate in
                        candidateRow(candidate)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func candidateRow(_ candidate: DictionaryService.Candidate) -> some View {
        Button {
            onSelect(candidate.english)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(candidate.english)
                    .font(Theme.serif(20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if !candidate.gloss.isEmpty {
                    // ECDICT glosses use literal "\n" between POS lines —
                    // unescape so they render as actual line breaks here.
                    Text(candidate.gloss.replacingOccurrences(of: "\\n", with: "\n"))
                        .font(Theme.serif(14))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.rule, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Theme.inkQuiet.opacity(0.5))
            Text("synonyms.empty")
                .font(.subheadline)
                .foregroundStyle(Theme.inkQuiet)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func load() async {
        let results = await DictionaryService.shared.reverseLookupWithGlosses(
            chinese, limit: Self.candidateLimit
        )
        candidates = results
        isLoading = false
    }
}
