# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

MiniNotes is a macOS menu bar app (no Dock icon; `LSUIElement = true`) with a live-preview Markdown editor. The UI is a SwiftUI/AppKit popover wrapping a WKWebView that runs a CodeMirror 6 editor bundled from JavaScript.

## Current Version

**v0.1.0** — update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` (both must match) when releasing a new version, then run `xcodegen generate`.

## Build Commands

### JS Editor Bundle (required after any change to `build/src/editor.js` or `editor.html`)

```bash
cd build && npm run build
```

This bundles and minifies `build/src/editor.js` into `MiniNotes/Resources/editor-bundle.js` using esbuild. The Swift app reads this file at runtime and inlines it into the HTML.

### macOS App

Open `MiniNotes.xcodeproj` in Xcode and use Cmd+R to run. There is no CLI build command configured.

### Regenerate Xcode project (required after any change to `project.yml`)

```bash
xcodegen generate
```

## Architecture

### Startup flow

`MiniNotesApp` (SwiftUI `@main`) -> `AppDelegate` -> `StatusBarController`

`StatusBarController` owns:
- `NSStatusItem` (menu bar icon: `square.and.pencil` SF Symbol, 16pt medium)
- `NSPopover` (620x500, `.applicationDefined` behavior)
- `NotesStore` (single source of truth for note content and app state)
- `EventMonitor` (closes popover on outside clicks)

### View state machine

`ContentView` switches between two root views based on `NotesStore.isFileOpen`:

- **`LandingView`** — shown on fresh start (no previously stored file) or after clicking the exit button. Lets the user open an existing `.md` file, create a new one, or reopen the most recently closed file.
- **Editor view** — toolbar (`filename | pin | Open in Obsidian | exit`) + `MarkdownEditorView` (WKWebView).

Clicking the exit button calls `NotesStore.closeFile()`: flushes to disk, records `recentFileURL`, sets `isFileOpen = false`.
Picking a file from `LandingView` calls `NotesStore.changeFile(to:)`: loads content, sets `isFileOpen = true`.

### Editor bridge (Swift <-> JavaScript)

The editor is a `WKWebView` rendering `editor.html` with `editor-bundle.js` inlined. Communication is bidirectional:

- **JS -> Swift**: `window.webkit.messageHandlers.contentChanged.postMessage(text)` triggers `NotesStore.save(_:)`
- **JS -> Swift**: `window.webkit.messageHandlers.openURL.postMessage(url)` opens links via `NSWorkspace`
- **Swift -> JS**: `webView.evaluateJavaScript(...)` calls these global functions defined in `editor.js`:
  - `setInitialContent(content)` — called once after page load
  - `resumeEditor(content)` — called when popover opens; recreates editor if it was destroyed
  - `suspendEditor()` — called when popover closes; destroys the CodeMirror view to free resources

### Persistence

`NotesStore` saves the file on popover close (`flush()`) and on exit button click (`closeFile()`). The last-used file path is stored in `UserDefaults` under key `notesFilePath`. On first launch (no stored path), `LandingView` is shown instead of the editor.

### JavaScript editor (`build/src/editor.js`)

Built on CodeMirror 6. Key features:
- **`livePreviewPlugin`**: walks the syntax tree on every doc/selection change, hides Markdown syntax markers (heading `#`, bold `**`, italic `*`, links) when the cursor is not on that line/range, and applies CSS classes for styled rendering.
- **`emptyLineSelectionPlugin`**: detects empty lines within the current selection and adds class `lp-empty-in-sel`, which shows a thin left-edge highlight strip (native browser selection skips empty lines).
- **Tables**: rendered as interactive HTML widgets via `TableWidget` (`WidgetType`); cells are editable `contenteditable` divs.
- **Checkboxes**: `- [ ]` / `- [x]` task list items rendered as clickable checkbox widgets.
- **Ordered list auto-renumber**: `renumberOrderedLists` keeps list numbers correct on every edit.
- **`drawSelection` is NOT used** — native browser selection is kept; the empty-line plugin fills the gap.

CSS classes applied by the plugin: `lp-h1`–`lp-h6`, `lp-strong`, `lp-em`, `lp-code`, `lp-fenced-line`, `lp-link`, `lp-bullet`, `lp-bullet-line`, `lp-ordered-line`, `lp-checkbox`, `lp-checkbox-checked`, `lp-empty-in-sel`.

Decoration ordering rules: line decorations before mark decorations; overlapping `Decoration.replace` items are deduplicated.

## Key Files

| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen spec — edit versions here, then run `xcodegen generate` |
| `MiniNotes/App/AppDelegate.swift` | App entry, delegates to `StatusBarController` |
| `MiniNotes/StatusBar/StatusBarController.swift` | Menu bar icon, popover lifecycle, event monitor |
| `MiniNotes/Store/NotesStore.swift` | `isFileOpen`, `recentFileURL`, content, debounced persistence |
| `MiniNotes/Views/ContentView.swift` | Root view: switches between `LandingView` and editor |
| `MiniNotes/Views/LandingView.swift` | Landing page: file picker, reopen recent, author info |
| `MiniNotes/Views/MarkdownEditorView.swift` | `NSViewRepresentable` wrapping WKWebView; JS bridge |
| `MiniNotes/Views/SettingsView.swift` | File-location settings sheet (opened from toolbar filename button) |
| `MiniNotes/Helpers/LocalizationHelper.swift` | All UI strings (EN/ZH), notification name extensions |
| `MiniNotes/Assets.xcassets/` | App icon (notebook + pencil, lavender bg) at all required sizes |
| `MiniNotes/Resources/editor.html` | HTML shell; JS bundle is inlined at load time |
| `build/src/editor.js` | CodeMirror 6 editor + live-preview decorations |
| `build/package.json` | JS dependencies and esbuild script |

## Typography

All UI text uses two fonts (assumed installed in `~/Library/Fonts/`):
- **LXGW WenKai Medium** (`LXGWWenKai-Medium`) — all body/UI text
- **Maple Mono NF CN Regular** (`MapleMono-NF-CN-Regular`) — monospace/code contexts, version string

## Release

See `~/.claude/rules/macos-sign-release.md` for the full signing, notarization, and GitHub publish workflow.
