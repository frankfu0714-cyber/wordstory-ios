import SwiftUI

struct ContentView: View {
    @State private var showSettings = false

    var body: some View {
        TabView {
            WordsView(showSettings: $showSettings)
                .tabItem {
                    Label("tab.words", systemImage: "book.closed")
                }
            StoryView(showSettings: $showSettings)
                .tabItem {
                    Label("tab.story", systemImage: "text.book.closed.fill")
                }
            SavedStoriesView(showSettings: $showSettings)
                .tabItem {
                    Label("saved.tab", systemImage: "heart.fill")
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Word.self, SavedStory.self], inMemory: true)
}
