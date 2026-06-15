import SwiftUI

/// Shown when the user taps a highlighted word in a generated story.
struct WordDetailModal: View {
    @Environment(\.dismiss) private var dismiss
    let word: Word

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(word.sourceText)
                    .font(Theme.serif(28, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 4)

                if !word.definition.isEmpty {
                    Text(word.definition)
                        .font(.body)
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(3)
                } else {
                    Text("detail.no_definition")
                        .font(.body.italic())
                        .foregroundStyle(Theme.inkQuiet)
                }

                if !word.example.isEmpty {
                    Text(word.example)
                        .font(Theme.serif(16).italic())
                        .foregroundStyle(Theme.inkQuiet)
                        .lineSpacing(4)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Theme.rule)
                                .frame(width: 2)
                        }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Word.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = ModelContext(container)
    let w = Word(
        sourceText: "serendipity",
        definition: "偶然發現美好事物的能力或機運。常用於描述意外卻幸運的相遇或發現。",
        example: "Their meeting was pure serendipity — neither expected the other on that train.",
        direction: .enToZh
    )
    ctx.insert(w)
    return WordDetailModal(word: w)
        .modelContainer(container)
}
