import { EditorView, ViewPlugin, Decoration, keymap } from "@codemirror/view"
import { EditorState, RangeSetBuilder } from "@codemirror/state"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { syntaxTree } from "@codemirror/language"
import { defaultKeymap, historyKeymap, history } from "@codemirror/commands"

// ─── Helpers ─────────────────────────────────────────────────────────────────

function cursorOnLine(state, lineFrom, lineTo) {
  for (const sel of state.selection.ranges) {
    if (sel.from <= lineTo && sel.to >= lineFrom) return true
  }
  return false
}

function cursorInRange(state, from, to) {
  for (const sel of state.selection.ranges) {
    if (sel.from < to && sel.to > from) return true
  }
  return false
}

function emphasisMarks(node) {
  const result = []
  const cur = node.node.cursor()
  if (cur.firstChild()) do {
    if (cur.name === "EmphasisMark") result.push([cur.from, cur.to])
  } while (cur.nextSibling())
  return result
}

// ─── Live Preview Decoration Builder ─────────────────────────────────────────

const HEADING_CLASS = {
  ATXHeading1: "lp-h1", ATXHeading2: "lp-h2", ATXHeading3: "lp-h3",
  ATXHeading4: "lp-h4", ATXHeading5: "lp-h5", ATXHeading6: "lp-h6",
}

function buildDecorations(view) {
  const { state } = view
  const docLen = state.doc.length

  // Each item: { from, to, deco, isLine, isAtomic }
  // isLine   = true  → Decoration.line (from===to, must be at line start)
  // isAtomic = true  → Decoration.replace (must not overlap each other)
  // else            → Decoration.mark (may overlap)
  const items = []

  function safeLineFrom(pos) {
    if (pos < 0 || pos > docLen) return -1
    return state.doc.lineAt(pos).from
  }

  function addLine(pos, cls) {
    const lf = safeLineFrom(pos)
    if (lf < 0) return
    items.push({ from: lf, to: lf, deco: Decoration.line({ class: cls }), isLine: true, isAtomic: false })
  }

  function addMark(from, to, cls) {
    if (from >= to || from < 0 || to > docLen) return
    items.push({ from, to, deco: Decoration.mark({ class: cls }), isLine: false, isAtomic: false })
  }

  function addReplace(from, to) {
    if (from >= to || from < 0 || to > docLen) return
    items.push({ from, to, deco: Decoration.replace({}), isLine: false, isAtomic: true })
  }

  syntaxTree(state).iterate({
    enter(node) {
      const { name, from, to } = node
      if (from >= docLen) return false

      // ── ATX Headings ─────────────────────────────────────────────────────
      if (name in HEADING_CLASS) {
        const line = state.doc.lineAt(from)
        addLine(line.from, HEADING_CLASS[name])

        const markNode = node.node.firstChild
        if (markNode?.name !== "HeaderMark") return false

        if (cursorOnLine(state, line.from, line.to)) {
          addMark(markNode.from, markNode.to, "lp-syntax-dim")
        } else {
          const hasSpace = state.doc.sliceString(markNode.to, markNode.to + 1) === " "
          addReplace(markNode.from, markNode.to + (hasSpace ? 1 : 0))
        }
        return false
      }

      // ── Strong (**bold**) ─────────────────────────────────────────────────
      if (name === "StrongEmphasis") {
        if (!cursorInRange(state, from, to)) {
          const mr = emphasisMarks(node)
          if (mr.length >= 2) {
            const [open, close] = [mr[0], mr[mr.length - 1]]
            if (open[1] < close[0]) {
              addReplace(open[0], open[1])
              addReplace(close[0], close[1])
              addMark(open[1], close[0], "lp-strong")
            }
          }
        }
        return false
      }

      // ── Emphasis (*italic*) ───────────────────────────────────────────────
      if (name === "Emphasis") {
        if (!cursorInRange(state, from, to)) {
          const mr = emphasisMarks(node)
          if (mr.length >= 2) {
            const [open, close] = [mr[0], mr[mr.length - 1]]
            if (open[1] < close[0]) {
              addReplace(open[0], open[1])
              addReplace(close[0], close[1])
              addMark(open[1], close[0], "lp-em")
            }
          }
        }
        return false
      }

      // ── Inline code ───────────────────────────────────────────────────────
      if (name === "InlineCode") {
        if (from < to) addMark(from, to, "lp-code")
        return false
      }

      // ── Fenced code block ─────────────────────────────────────────────────
      if (name === "FencedCode") {
        const startLine = state.doc.lineAt(from)
        const endLine   = state.doc.lineAt(Math.min(to, docLen))
        for (let n = startLine.number; n <= endLine.number; n++) {
          if (n < 1 || n > state.doc.lines) continue
          addLine(state.doc.line(n).from, "lp-fenced-line")
        }
        // Dim the fence marker lines
        addMark(startLine.from, startLine.to, "lp-syntax-dim")
        if (endLine.number !== startLine.number && endLine.from < endLine.to) {
          addMark(endLine.from, endLine.to, "lp-syntax-dim")
        }
        return false
      }
    },
  })

  // Sort: line decos first (they have from===to), then by from asc, then to asc
  items.sort((a, b) => {
    if (a.from !== b.from) return a.from - b.from
    if (a.isLine !== b.isLine) return a.isLine ? -1 : 1
    return a.to - b.to
  })

  // Strip overlapping atomics (replace decorations must not overlap)
  let lastAtomicEnd = -1
  const clean = items.filter(item => {
    if (!item.isAtomic) return true
    if (item.from >= lastAtomicEnd) { lastAtomicEnd = item.to; return true }
    return false
  })

  // Build with RangeSetBuilder – requires strictly ascending order, no throws
  const builder = new RangeSetBuilder()
  for (const { from, to, deco } of clean) {
    try {
      builder.add(from, to, deco)
    } catch {
      // skip any item that violates ordering (shouldn't happen after sort)
    }
  }
  return builder.finish()
}

// ─── Plugin ───────────────────────────────────────────────────────────────────

const livePreviewPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = buildDecorations(view) }
    update(u) {
      if (u.docChanged || u.selectionSet)
        this.decorations = buildDecorations(u.view)
    }
  },
  { decorations: v => v.decorations },
)

// ─── Theme ────────────────────────────────────────────────────────────────────

const editorTheme = EditorView.baseTheme({
  "&": { height: "100%" },
  ".cm-scroller": {
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
    fontSize: "14px",
    lineHeight: "1.75",
    overflow: "auto",
  },
  ".cm-content": { padding: "18px 22px", minHeight: "100%", caretColor: "auto" },
  ".cm-line":    { padding: "1px 0" },
  ".cm-cursor":  { borderLeftWidth: "2px" },
  ".cm-focused": { outline: "none" },

  ".lp-h1": { fontSize: "1.9em",  fontWeight: "700", lineHeight: "1.3" },
  ".lp-h2": { fontSize: "1.55em", fontWeight: "700", lineHeight: "1.3" },
  ".lp-h3": { fontSize: "1.25em", fontWeight: "600", lineHeight: "1.3" },
  ".lp-h4": { fontSize: "1.1em",  fontWeight: "600" },
  ".lp-h5": { fontSize: "1em",    fontWeight: "600" },
  ".lp-h6": { fontSize: "0.95em", fontWeight: "600" },

  ".lp-syntax-dim": { color: "#aaa", fontWeight: "400 !important" },

  ".lp-strong": { fontWeight: "700" },
  ".lp-em":     { fontStyle: "italic" },
  ".lp-code": {
    fontFamily: '"SF Mono", Menlo, Monaco, monospace',
    fontSize: "0.88em",
    background: "rgba(128,128,128,0.15)",
    borderRadius: "3px",
    padding: "1px 4px",
  },
  ".lp-fenced-line": {
    fontFamily: '"SF Mono", Menlo, Monaco, monospace',
    fontSize: "0.88em",
    background: "rgba(128,128,128,0.08)",
  },
})

// ─── Public API ───────────────────────────────────────────────────────────────

let _view = null
let _onChange = null

function buildExtensions() {
  return [
    history(),
    keymap.of([...defaultKeymap, ...historyKeymap]),
    markdown({ base: markdownLanguage }),
    EditorView.lineWrapping,
    livePreviewPlugin,
    editorTheme,
    EditorView.updateListener.of((update) => {
      if (update.docChanged && _onChange) _onChange(update.view.state.doc.toString())
    }),
  ]
}

function makeView(content, parent) {
  return new EditorView({
    state: EditorState.create({ doc: content, extensions: buildExtensions() }),
    parent,
  })
}

// Called once from HTML on page load
window.setupEditor = function (initialContent, onChange) {
  _onChange = onChange
  _view = makeView(initialContent, document.getElementById("editor"))
  return _view
}

// Called from Swift after didFinish to inject saved notes
window.setInitialContent = function (content) {
  if (!_view) return
  _view.dispatch({
    changes: { from: 0, to: _view.state.doc.length, insert: content },
    selection: { anchor: content.length },
  })
  _view.focus()
}

// Called from Swift when popover closes - stops all RAF/timers
window.suspendEditor = function () {
  if (_view) { _view.destroy(); _view = null }
}

// Called from Swift when popover opens - recreates editor with latest content
window.resumeEditor = function (content) {
  if (!_onChange) return
  if (_view) {
    // Already alive (e.g. first open): just sync content
    const current = _view.state.doc.toString()
    if (current !== content) {
      _view.dispatch({ changes: { from: 0, to: current.length, insert: content } })
    }
    _view.focus()
    return
  }
  // Recreate after suspend
  const container = document.getElementById("editor")
  if (!container) return
  container.innerHTML = ""
  _view = makeView(content, container)
  _view.focus()
}
