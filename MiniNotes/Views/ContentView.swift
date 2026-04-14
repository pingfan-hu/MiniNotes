import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var notesStore: NotesStore
    @State private var showingSettings = false
    @State private var isPinned = false

    private var displayFilename: String {
        notesStore.fileURL.lastPathComponent
    }

    var body: some View {
        if notesStore.isFileOpen {
            editorView
        } else {
            LandingView()
                .environmentObject(notesStore)
        }
    }

    private var editorView: some View {
        VStack(spacing: 0) {
            // Tab bar: [pin | filename | Open in Obsidian | exit]
            HStack(spacing: 0) {
                // Pin toggle
                PinButton(
                    isPinned: isPinned,
                    corners: RectangleCornerRadii(
                        topLeading: 10, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0
                    )
                ) {
                    togglePin()
                }
                .help(isPinned ? L.pinTooltipUnpin : L.pinTooltipPin)

                ToolbarActionButton(
                    corners: RectangleCornerRadii(
                        topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0
                    )
                ) {
                    showingSettings = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "note.text")
                            .font(.system(size: 12))
                        Text(displayFilename)
                            .font(Font.custom("LXGWWenKai-Medium", size: 14))
                            .lineLimit(1)
                    }
                }

                ToolbarActionButton(
                    corners: RectangleCornerRadii(
                        topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0
                    )
                ) {
                    openInObsidian()
                } label: {
                    Text(L.buttonOpenInObsidian)
                        .font(Font.custom("LXGWWenKai-Medium", size: 14))
                        .lineLimit(1)
                }

                // Exit: save + return to landing page
                ExitButton(
                    corners: RectangleCornerRadii(
                        topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 10
                    )
                ) {
                    notesStore.closeFile()
                }
                .help(L.exitTooltip)
            }
            .frame(height: 30)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()
                .padding(.top, 6)

            MarkdownEditorView()
                .environmentObject(notesStore)
        }
        .frame(width: 620, height: 500)
        .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.3))
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
                .environmentObject(notesStore)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            showingSettings = false
        }
    }

    private func togglePin() {
        isPinned.toggle()
        NotificationCenter.default.post(name: .miniNotesTogglePin, object: isPinned)
    }

    private func openInObsidian() {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "md.obsidian") != nil else {
            return
        }
        let path = notesStore.fileURL.path
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "obsidian://open?path=\(encoded)") else { return }
        let opened = NSWorkspace.shared.open(url)
        if opened {
            NotificationCenter.default.post(name: .miniNotesClosePopover, object: nil)
        }
    }
}

private struct ExitButton: View {
    let corners: RectangleCornerRadii
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
            }
            action()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .background(
                    Group {
                        if isPressed {
                            Color(red: 0.42, green: 0.50, blue: 0.77).opacity(0.2)
                        } else if isHovering {
                            Color(red: 0.42, green: 0.50, blue: 0.77).opacity(0.1)
                        } else {
                            Color.clear
                        }
                    }
                )
                .clipShape(UnevenRoundedRectangle(cornerRadii: corners))
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

private struct PinButton: View {
    let isPinned: Bool
    let corners: RectangleCornerRadii
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
            }
            action()
        }) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11))
                .foregroundColor(isPinned ? Color(red: 0.42, green: 0.50, blue: 0.77) : .secondary)
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .background(
                    Group {
                        if isPressed {
                            Color(red: 0.42, green: 0.50, blue: 0.77).opacity(0.2)
                        } else if isHovering {
                            Color(red: 0.42, green: 0.50, blue: 0.77).opacity(0.1)
                        } else {
                            Color.clear
                        }
                    }
                )
                .clipShape(UnevenRoundedRectangle(cornerRadii: corners))
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

private struct ToolbarActionButton<Label: View>: View {
    let corners: RectangleCornerRadii
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
            }
            action()
        }) {
            label()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    Group {
                        if isPressed {
                            Color(red: 0.42, green: 0.50, blue: 0.77).opacity(0.2)
                        } else if isHovering {
                            Color(red: 0.42, green: 0.50, blue: 0.77).opacity(0.1)
                        } else {
                            Color.clear
                        }
                    }
                )
                .clipShape(UnevenRoundedRectangle(cornerRadii: corners))
                .foregroundColor(Color(red: 0.42, green: 0.50, blue: 0.77))
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
