import SwiftUI

struct ContentView: View {
    @EnvironmentObject var notesStore: NotesStore

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.secondary)
                Text("MiniNotes")
                    .font(.headline)
                Spacer()
                Text("Auto-saved")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            MarkdownEditorView()
                .environmentObject(notesStore)
        }
        .frame(width: 620, height: 500)
    }
}
