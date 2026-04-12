import SwiftUI
import AppKit

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
                    .font(.system(size: 14, weight: .regular))

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayFilename)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(displayDirectory)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(L.autoSaved)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                ToolbarButton(title: L.buttonObsidian) {
                    openInObsidian()
                }

                ToolbarButton(title: L.buttonChoose) {
                    showingSettings = true
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            MarkdownEditorView()
                .environmentObject(notesStore)
        }
        .frame(width: 620, height: 500)
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
                .environmentObject(notesStore)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            showingSettings = false
        }
    }

    private func openInObsidian() {
        let path = notesStore.fileURL.path
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "obsidian://open?path=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ToolbarButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(red: 0.42, green: 0.50, blue: 0.77))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.42, green: 0.50, blue: 0.77).opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}
