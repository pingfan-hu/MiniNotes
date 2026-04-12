import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var notesStore: NotesStore
    @Binding var isPresented: Bool

    private var displayPath: String {
        let path = notesStore.fileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("File Location")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Current file")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(displayPath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button("Open Existing File...") {
                    openExistingFile()
                }
                .buttonStyle(.bordered)

                Button("Create New File...") {
                    createNewFile()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 240)
    }

    private func openExistingFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Markdown file"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        notesStore.changeFile(to: url)
        isPresented = false
    }

    private func createNewFile() {
        let panel = NSSavePanel()
        panel.title = "Create a new Markdown file"
        panel.nameFieldStringValue = "notes.md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        notesStore.changeFile(to: url)
        isPresented = false
    }
}
