import { EditorView, ViewPlugin, Decoration, WidgetType, keymap } from "@codemirror/view"
import { EditorState, RangeSetBuilder } from "@codemirror/state"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { syntaxTree } from "@codemirror/language"
import { defaultKeymap, historyKeymap, history } from "@codemirror/commands"
import { marked } from "marked"

marked.use({ gfm: true, breaks: false })

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

// ─── Widgets ─────────────────────────────────────────────────────────────────

class BulletWidget extends WidgetType {
  eq() { return true }
  ignoreEvent() { return true }
  toDOM() {
    const s = document.createElement("span")
    s.className = "lp-bullet"
    s.textContent = "•\u00a0"
    return s
  }
}

class CheckboxWidget extends WidgetType {
  constructor(checked) { super(); this.checked = checked }
  eq(o) { return this.checked === o.checked }
  ignoreEvent() { return false }   // let clicks through to domEventHandlers
  toDOM() {
    const s = document.createElement("span")
    s.className = "lp-checkbox"
    s.textContent = this.checked ? "☑\u00a0" : "☐\u00a0"
    return s
  }
}

class TableWidget extends WidgetType {
  constructor(html) { super(); this.html = html }
  eq(o) { return this.html === o.html }
  ignoreEvent() { return false }
  toDOM() {
    const wrap = document.createElement("div")
    wrap.className = "lp-table-wrap"
    wrap.innerHTML = this.html
    return wrap
  }
}

// ─── Decoration builder ───────────────────────────────────────────────────────

const HEADING_CLASS = {
  ATXHeading1: "lp-h1", ATXHeading2: "lp-h2", ATXHeading3: "lp-h3",
  ATXHeading4: "lp-h4", ATXHeading5: "lp-h5", ATXHeading6: "lp-h6",
}

function buildDecorations(view) {
  const { state } = view
  const docLen = state.doc.length
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
  function addWidget(from, to, widget) {
    if (from < 0 || to > docLen || from > to) return
    // Do NOT use block:true — it requires single-line ranges and crashes on multi-line tables
    items.push({ from, to, deco: Decoration.replace({ widget }), isLine: false, isAtomic: true })
  }

  try {
    syntaxTree(state).iterate({
      enter(node) {
        const { name, from, to } = node
        if (from >= docLen) return false

        // ── Headings ────────────────────────────────────────────────────────
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

        // ── Bold ─────────────────────────────────────────────────────────────
        if (name === "StrongEmphasis") {
          if (!cursorInRange(state, from, to)) {
            const mr = emphasisMarks(node)
            if (mr.length >= 2) {
              const [open, close] = [mr[0], mr[mr.length - 1]]
              if (open[1] < close[0]) {
                addReplace(open[0], open[1]); addReplace(close[0], close[1])
                addMark(open[1], close[0], "lp-strong")
              }
            }
          }
          return false
        }

        // ── Italic ───────────────────────────────────────────────────────────
        if (name === "Emphasis") {
          if (!cursorInRange(state, from, to)) {
            const mr = emphasisMarks(node)
            if (mr.length >= 2) {
              const [open, close] = [mr[0], mr[mr.length - 1]]
              if (open[1] < close[0]) {
                addReplace(open[0], open[1]); addReplace(close[0], close[1])
                addMark(open[1], close[0], "lp-em")
              }
            }
          }
          return false
        }

        // ── Inline code ──────────────────────────────────────────────────────
        if (name === "InlineCode") {
          if (from < to) addMark(from, to, "lp-code")
          return false
        }

        // ── Fenced code ──────────────────────────────────────────────────────
        if (name === "FencedCode") {
          const startLine = state.doc.lineAt(from)
          const endLine   = state.doc.lineAt(Math.min(to, docLen))
          for (let n = startLine.number; n <= endLine.number; n++) {
            if (n < 1 || n > state.doc.lines) continue
            addLine(state.doc.line(n).from, "lp-fenced-line")
          }
          addMark(startLine.from, startLine.to, "lp-syntax-dim")
          if (endLine.number !== startLine.number && endLine.from < endLine.to)
            addMark(endLine.from, endLine.to, "lp-syntax-dim")
          return false
        }

        // ── Link [text](url) ─────────────────────────────────────────────────
        if (name === "Link") {
          if (!cursorInRange(state, from, to)) {
            const raw = state.doc.sliceString(from, to)
            const closeIdx = raw.indexOf("](")
            if (closeIdx > 0) {
              addReplace(from, from + 1)           // hide [
              addReplace(from + closeIdx, to)      // hide ](url)
              addMark(from + 1, from + closeIdx, "lp-link")
            }
          }
          return false
        }

        // ── Bullet list mark (-, *, +) ───────────────────────────────────────
        if (name === "ListMark") {
          const parent = node.node.parent
          if (parent?.name === "ListItem" && parent?.parent?.name === "BulletList") {
            if (!cursorInRange(state, from, to)) {
              const hasSpace = to < docLen && state.doc.sliceString(to, to + 1) === " "
              addWidget(from, to + (hasSpace ? 1 : 0), new BulletWidget())
            }
          }
          return false
        }

        // ── Task checkboxes [ ] / [x] ────────────────────────────────────────
        if (name === "TaskMarker") {
          if (!cursorInRange(state, from, to)) {
            const raw = state.doc.sliceString(from, to)
            const checked = /\[x\]/i.test(raw)
            addWidget(from, to, new CheckboxWidget(checked))
          }
          return false
        }

        // ── GFM Table ────────────────────────────────────────────────────────
        if (name === "Table") {
          if (!cursorInRange(state, from, to)) {
            try {
              const firstLine = state.doc.lineAt(from)
              const lastLine  = state.doc.lineAt(Math.min(to, docLen - 1))
              const tableMd   = state.doc.sliceString(firstLine.from, lastLine.to)
              const html      = marked.parse(tableMd)
              if (html.includes("<table")) {
                // Replace the first table line with the rendered widget.
                // Single-line Decoration.replace is always valid — no block:true needed.
                addWidget(firstLine.from, firstLine.to, new TableWidget(html))
                // Hide every subsequent table line (single-line replacements + CSS class)
                let linePos = firstLine.to + 1
                while (linePos <= lastLine.from) {
                  const ln = state.doc.lineAt(linePos)
                  addLine(ln.from, "lp-table-source")
                  if (ln.from < ln.to) {
                    items.push({ from: ln.from, to: ln.to, deco: Decoration.replace({}), isLine: false, isAtomic: true })
                  }
                  if (ln.from >= lastLine.from) break
                  linePos = ln.to + 1
                }
              }
            } catch (_) {}
          }
          return false
        }
      },
    })
  } catch (_) {}

  // Sort: line decos first, then by from asc, then to asc
  items.sort((a, b) => {
    if (a.from !== b.from) return a.from - b.from
    if (a.isLine !== b.isLine) return a.isLine ? -1 : 1
    return a.to - b.to
  })

  // Strip overlapping atomics
  let lastAtomicEnd = -1
  const clean = items.filter(item => {
    if (!item.isAtomic) return true
    if (item.from >= lastAtomicEnd) { lastAtomicEnd = item.to; return true }
    return false
  })

  const builder = new RangeSetBuilder()
  for (const { from, to, deco } of clean) {
    try { builder.add(from, to, deco) } catch (_) {}
  }
  try { return builder.finish() } catch (_) { return Decoration.none }
}

// ─── Plugin ───────────────────────────────────────────────────────────────────

const livePreviewPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = buildDecorations(view) }
    update(u) {
      if (u.docChanged || u.selectionSet) this.decorations = buildDecorations(u.view)
    }
  },
  { decorations: v => v.decorations },
)

// ─── Interaction handlers ─────────────────────────────────────────────────────

function openURL(url) {
  if (window.webkit?.messageHandlers?.openURL) {
    window.webkit.messageHandlers.openURL.postMessage(url)
  }
}

const interactionHandlers = EditorView.domEventHandlers({
  mousedown(event, view) {
    const target = event.target

    // ── Checkbox toggle ──────────────────────────────────────────────────
    if (target.classList?.contains("lp-checkbox")) {
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY }, false)
      if (pos != null) {
        // Walk syntax tree to find TaskMarker at or near pos
        const tree = syntaxTree(view.state)
        let found = null
        tree.iterate({
          from: Math.max(0, pos - 1),
          to: Math.min(view.state.doc.length, pos + 4),
          enter(n) {
            if (n.name === "TaskMarker") { found = { from: n.from, to: n.to }; return false }
          }
        })
        if (found) {
          const cur = view.state.doc.sliceString(found.from, found.to)
          view.dispatch({ changes: { from: found.from, to: found.to, insert: /\[x\]/i.test(cur) ? "[ ]" : "[x]" } })
          event.preventDefault()
          return true
        }
      }
    }

    // ── Link click → open URL ────────────────────────────────────────────
    if (target.classList?.contains("lp-link") || target.closest?.(".lp-link")) {
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY }, false)
      if (pos != null) {
        const tree = syntaxTree(view.state)
        let url = null
        // Resolve the node at click position and walk up to find Link
        let cur = tree.resolve(pos, 1)
        while (cur && cur.name !== "Document") {
          if (cur.name === "Link") {
            if (!cursorInRange(view.state, cur.from, cur.to)) {
              const raw = view.state.doc.sliceString(cur.from, cur.to)
              const closeIdx = raw.indexOf("](")
              if (closeIdx > 0) url = raw.slice(closeIdx + 2, -1)
            }
            break
          }
          cur = cur.parent
        }
        if (url) {
          openURL(url)
          // Don't preventDefault — cursor still moves to the link (showing raw for editing)
        }
      }
    }

    return false
  },
})

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
  ".lp-link": {
    color: "#4a7cf7",
    textDecoration: "underline",
    cursor: "pointer",
  },
  ".lp-bullet": {
    userSelect: "none",
  },
  ".lp-checkbox": {
    cursor: "pointer",
    userSelect: "none",
  },
  ".lp-table-source": {
    fontSize: "0 !important",
    lineHeight: "0 !important",
    padding: "0 !important",
    height: "0 !important",
    overflow: "hidden !important",
    userSelect: "none",
  },
  ".lp-table-wrap": {
    display: "block",
    margin: "4px 0",
    overflowX: "auto",
  },
  ".lp-table-wrap table": {
    borderCollapse: "collapse",
    fontSize: "14px",
    lineHeight: "1.6",
    width: "100%",
  },
  ".lp-table-wrap th": {
    border: "1px solid rgba(128,128,128,0.3)",
    padding: "5px 12px",
    textAlign: "left",
    background: "rgba(128,128,128,0.08)",
    fontWeight: "600",
  },
  ".lp-table-wrap td": {
    border: "1px solid rgba(128,128,128,0.3)",
    padding: "5px 12px",
    textAlign: "left",
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
    interactionHandlers,
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

window.setupEditor = function (initialContent, onChange) {
  _onChange = onChange
  _view = makeView(initialContent, document.getElementById("editor"))
  return _view
}

window.setInitialContent = function (content) {
  if (!_view) return
  _view.dispatch({
    changes: { from: 0, to: _view.state.doc.length, insert: content },
    selection: { anchor: content.length },
  })
  _view.focus()
}

window.suspendEditor = function () {
  if (_view) { _view.destroy(); _view = null }
}

window.resumeEditor = function (content) {
  if (!_onChange) return
  if (_view) {
    const current = _view.state.doc.toString()
    if (current !== content)
      _view.dispatch({ changes: { from: 0, to: current.length, insert: content } })
    _view.focus()
    return
  }
  const container = document.getElementById("editor")
  if (!container) return
  container.innerHTML = ""
  _view = makeView(content, container)
  _view.focus()
}
