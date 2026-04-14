import SwiftUI
import AppKit

struct LandingView: View {
    @EnvironmentObject var notesStore: NotesStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon + title + version
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)

                Text("MiniNotes")
                    .font(Font.custom("LXGWWenKai-Medium", size: 22))
                    .foregroundColor(.primary)

                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                    .font(Font.custom("MapleMono-NF-CN-Regular", size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer().frame(height: 32)

            // Action buttons
            VStack(spacing: 10) {
                if let recent = notesStore.recentFileURL {
                    LandingButton(title: L.reopenFile(name: recent.lastPathComponent), isAccent: true) {
                        notesStore.changeFile(to: recent)
                    }
                }

                LandingButton(title: L.settingsOpenExisting) {
                    openExistingFile()
                }

                LandingButton(title: L.settingsCreateNew) {
                    createNewFile()
                }
            }
            .frame(width: 260)

            Spacer()

            // Author info
            VStack(spacing: 3) {
                Text("Pingfan Hu")
                    .font(Font.custom("LXGWWenKai-Medium", size: 11))
                    .foregroundColor(.secondary)
                WebsiteLink(label: "pingfanhu.com", url: "https://pingfanhu.com")
            }
            .padding(.bottom, 14)
        }
        .frame(width: 620, height: 500)
        .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.3))
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
    }

    private func createNewFile() {
        let panel = NSSavePanel()
        panel.title = L.settingsPanelCreateTitle
        panel.nameFieldStringValue = "notes.md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        notesStore.changeFile(to: url)
    }
}

private struct WebsiteLink: View {
    let label: String
    let url: String

    @State private var isHovering = false

    var body: some View {
        Text(label)
            .font(Font.custom("MapleMono-NF-CN-Regular", size: 11))
            .foregroundColor(isHovering ? Color(red: 0.42, green: 0.50, blue: 0.77) : .secondary)
            .underline(isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture {
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                NotificationCenter.default.post(name: .miniNotesClosePopover, object: nil)
            }
    }
}

private struct LandingButton: View {
    let title: String
    var isAccent: Bool = false
    let action: () -> Void

    private let accent = Color(red: 0.42, green: 0.50, blue: 0.77)

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Font.custom("LXGWWenKai-Medium", size: 13))
                .foregroundColor(isAccent ? .white : accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isAccent
                              ? accent
                              : Color(nsColor: NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accent.opacity(isAccent ? 0 : 0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
