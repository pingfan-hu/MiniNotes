import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var notesStore: NotesStore
    @ObservedObject private var settings = AppSettings.shared
    @State private var showingSettings = false
    @State private var isPinned = false
    @State private var editorMode: EditorMode = .edit

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
            // Tab bar: [pin | filename …  [source|edit|view]  … Open in Obsidian | exit]
            ZStack {
                // Left + right items
                HStack(spacing: 0) {
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

                    Spacer(minLength: 96) // reserve space for the centered mode buttons

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

                    ExitButton(
                        corners: RectangleCornerRadii(
                            topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 10
                        )
                    ) {
                        notesStore.closeFile()
                    }
                    .help(L.exitTooltip)
                }

                // Centered mode buttons (float above the HStack)
                ModeButtonGroup(current: editorMode) { newMode in
                    setEditorMode(newMode)
                }
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
        .onChange(of: notesStore.isFileOpen) { isOpen in
            if isOpen { setEditorMode(.edit) }
        }
        .background(ModeShortcutHandler { mode in setEditorMode(mode) })
    }

    private func setEditorMode(_ mode: EditorMode) {
        editorMode = mode
        NotificationCenter.default.post(name: .miniNotesEditorModeChanged, object: mode.rawValue)
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

// MARK: - Keyboard shortcuts (Cmd+1/2/3)

/// Installs a local NSEvent monitor for Cmd+1/2/3 to switch editor modes.
/// The monitor is active only while the view (and thus the popover) is visible.
private struct ModeShortcutHandler: NSViewRepresentable {
    let onModeChange: (EditorMode) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            let mode: EditorMode?
            switch event.charactersIgnoringModifiers {
            case "1": mode = .source
            case "2": mode = .edit
            case "3": mode = .view
            default: mode = nil
            }
            if let mode {
                onModeChange(mode)
                return nil // consume the event
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var monitor: Any?
    }
}

// MARK: - Mode buttons

private struct ModeButtonGroup: View {
    let current: EditorMode
    let onSelect: (EditorMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ModeButton(
                icon: "chevron.left.forwardslash.chevron.right",
                mode: .source,
                current: current,
                tooltip: L.modeSourceTooltip,
                onSelect: onSelect
            )
            ModeButton(
                icon: "pencil.and.outline",
                mode: .edit,
                current: current,
                tooltip: L.modeEditTooltip,
                onSelect: onSelect
            )
            ModeButton(
                icon: "book",
                mode: .view,
                current: current,
                tooltip: L.modeViewTooltip,
                onSelect: onSelect
            )
        }
    }
}

private struct ModeButton: View {
    let icon: String
    let mode: EditorMode
    let current: EditorMode
    let tooltip: String
    let onSelect: (EditorMode) -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    private var isActive: Bool { current == mode }
    private let accent = Color(red: 0.42, green: 0.50, blue: 0.77)

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
            }
            onSelect(mode)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(isActive ? accent : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            isActive
                                ? accent.opacity(0.15)
                                : (isPressed ? accent.opacity(0.2) : (isHovering ? accent.opacity(0.08) : Color.clear))
                        )
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

// MARK: - Exit / Pin / ToolbarAction buttons

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
