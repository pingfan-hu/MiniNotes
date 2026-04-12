import SwiftUI

struct ContentView: View {
    @EnvironmentObject var notesStore: NotesStore
    @State private var showingSettings = false

    private var displayDirectory: String {
        let dir = notesStore.fileURL.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }

    private var displayFilename: String {
        notesStore.fileURL.lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayFilename)
                        .font(.headline)
                        .lineLimit(1)
                    Text(displayDirectory)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text("Auto-saved")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("File settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            MarkdownEditorView()
                .environmentObject(notesStore)
        }
        .frame(width: 620, height: 500)
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
                .environmentObject(notesStore)
        }
    }
}
