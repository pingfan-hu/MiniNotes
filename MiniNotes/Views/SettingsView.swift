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
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(L.settingsTitle)
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Divider()

            // Current file path
            VStack(alignment: .leading, spacing: 6) {
                Text(L.settingsCurrentFile)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Text(displayPath)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Actions
            HStack(spacing: 10) {
                SettingsActionButton(title: L.settingsOpenExisting) {
                    openExistingFile()
                }
                SettingsActionButton(title: L.settingsCreateNew) {
                    createNewFile()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            Spacer()

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(L.settingsDone) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 400, height: 240)
        .background(.ultraThinMaterial)
    }

    private func openExistingFile() {
        let panel = NSOpenPanel()
        panel.title = L.settingsPanelChooseTitle
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
        panel.title = L.settingsPanelCreateTitle
        panel.nameFieldStringValue = "notes.md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        notesStore.changeFile(to: url)
        isPresented = false
    }
}

private struct SettingsActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(Color(red: 0.42, green: 0.50, blue: 0.77))
    }
}
