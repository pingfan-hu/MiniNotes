# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

MiniNotes is a macOS menu bar app (no Dock icon; `LSUIElement = true`) with a live-preview Markdown editor. The UI is a SwiftUI/AppKit popover wrapping a WKWebView that runs a CodeMirror 6 editor bundled from JavaScript.

## Build Commands

### JS Editor Bundle (required after any change to `build/src/editor.js`)

```bash
cd build && npm run build
```

This bundles and minifies `build/src/editor.js` into `MiniNotes/Resources/editor-bundle.js` using esbuild. The Swift app reads this file at runtime and inlines it into the HTML.

### macOS App

Open `MiniNotes.xcodeproj` in Xcode and use Cmd+R to run. There is no CLI build command configured.

## Architecture

### Startup flow

`MiniNotesApp` (SwiftUI `@main`) -> `AppDelegate` -> `StatusBarController`

`StatusBarController` owns:
- `NSStatusItem` (the menu bar icon)
- `NSPopover` (620x500, `.transient` behavior)
- `NotesStore` (the single source of truth for note content)
- `EventMonitor` (closes popover on outside clicks)

### Editor bridge (Swift <-> JavaScript)

The editor is a `WKWebView` rendering `editor.html` with `editor-bundle.js` inlined. Communication is bidirectional:

- **JS -> Swift**: `window.webkit.messageHandlers.contentChanged.postMessage(text)` triggers `NotesStore.save(_:)`
- **Swift -> JS**: `webView.evaluateJavaScript(...)` calls these global functions defined in `editor.js`:
  - `setInitialContent(content)` — called once after page load
  - `resumeEditor(content)` — called when popover opens; recreates editor if it was destroyed
  - `suspendEditor()` — called when popover closes; destroys the CodeMirror view to free resources

### Persistence

`NotesStore` saves to `~/Library/Application Support/MiniNotes/notes.md` with a 0.5-second debounce. The file is read once at init.

### JavaScript editor (`build/src/editor.js`)

Built on CodeMirror 6. Implements a custom `livePreviewPlugin` (a `ViewPlugin`) that:
1. Walks the syntax tree on every doc/selection change
2. Hides Markdown syntax markers (heading `#`, bold `**`, italic `*`) when the cursor is not on that line/range
3. Applies CSS classes (`lp-h1`–`lp-h6`, `lp-strong`, `lp-em`, `lp-code`, `lp-fenced-line`) for styling

Decoration ordering rules: line decorations before mark decorations; overlapping `Decoration.replace` items are deduplicated.

## Key Files

| File | Purpose |
|------|---------|
| `MiniNotes/StatusBar/StatusBarController.swift` | Menu bar icon, popover lifecycle, event monitor |
| `MiniNotes/Store/NotesStore.swift` | In-memory state + debounced file persistence |
| `MiniNotes/Views/MarkdownEditorView.swift` | `NSViewRepresentable` wrapping WKWebView; JS bridge |
| `MiniNotes/Resources/editor.html` | HTML shell; JS bundle is inlined at load time |
| `build/src/editor.js` | CodeMirror 6 editor + live-preview decorations |
| `build/package.json` | JS dependencies and esbuild script |
