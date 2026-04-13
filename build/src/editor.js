import { EditorView, ViewPlugin, Decoration, WidgetType, keymap } from "@codemirror/view"
import { EditorState, RangeSetBuilder, Compartment, StateEffect } from "@codemirror/state"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { syntaxTree, HighlightStyle, syntaxHighlighting } from "@codemirror/language"
import { languages } from "@codemirror/language-data"
import { tags as t } from "@lezer/highlight"
import { defaultKeymap, historyKeymap, history } from "@codemirror/commands"
import { marked } from "marked"

marked.use({ gfm: true, breaks: false })

// ─── Syntax-highlight themes ──────────────────────────────────────────────────
// Colors mirror the user's code-light.theme / code-dark.theme files.

const lightHighlightStyle = HighlightStyle.define([
  { tag: [t.comment, t.lineComment, t.blockComment, t.docComment],
    color: "#6c675f", fontStyle: "italic" },
  { tag: [t.keyword, t.controlKeyword, t.definitionKeyword, t.operatorKeyword],
    color: "#876032" },
  { tag: [t.typeName, t.typeOperator, t.className],
    color: "#527594" },
  { tag: [t.function(t.name), t.function(t.variableName), t.function(t.propertyName)],
    color: "#9a4929" },
  { tag: [t.standard(t.name), t.standard(t.variableName)],
    color: "#9a4929" },
  { tag: [t.string, t.character, t.special(t.string)],
    color: "#3f643c" },
  { tag: [t.number, t.integer, t.float, t.bool],
    color: "#7c619a" },
  { tag: [t.constant(t.name), t.constant(t.variableName)],
    color: "#7c619a" },
  { tag: [t.annotation, t.meta, t.processingInstruction, t.moduleKeyword],
    color: "#7c619a" },
  { tag: t.operator,
    color: "#3d3929" },
  { tag: [t.attributeName, t.modifier],
    color: "#876032", fontStyle: "italic" },
  { tag: t.invalid,
    color: "#b05555", fontWeight: "bold" },
])

const darkHighlightStyle = HighlightStyle.define([
  { tag: [t.comment, t.lineComment, t.blockComment, t.docComment],
    color: "#938e87", fontStyle: "italic" },
  { tag: [t.keyword, t.controlKeyword, t.definitionKeyword, t.operatorKeyword],
    color: "#c4956a" },
  { tag: [t.typeName, t.typeOperator, t.className],
    color: "#7b9ebd" },
  { tag: [t.function(t.name), t.function(t.variableName), t.function(t.propertyName)],
    color: "#d97757" },
  { tag: [t.standard(t.name), t.standard(t.variableName)],
    color: "#d97757" },
  { tag: [t.string, t.character, t.special(t.string)],
    color: "#7da47a" },
  { tag: [t.number, t.integer, t.float, t.bool],
    color: "#a68bbf" },
  { tag: [t.constant(t.name), t.constant(t.variableName)],
    color: "#a68bbf" },
  { tag: [t.annotation, t.meta, t.processingInstruction, t.moduleKeyword],
    color: "#a68bbf" },
  { tag: t.operator,
    color: "#d4cfc6" },
  { tag: [t.attributeName, t.modifier],
    color: "#c4956a", fontStyle: "italic" },
  { tag: t.invalid,
    color: "#c67777", fontWeight: "bold" },
])

const highlightCompartment = new Compartment()

function isDarkMode() {
  return window.matchMedia("(prefers-color-scheme: dark)").matches
}
function currentHighlightExt() {
  return syntaxHighlighting(isDarkMode() ? darkHighlightStyle : lightHighlightStyle)
}

// Inject CSS variables for code-block backgrounds so they adapt to light/dark.
;(function() {
  const s = document.createElement("style")
  s.textContent = [
    ":root{--mn-code-bg:rgba(128,128,128,0.08);--mn-inline-bg:rgba(128,128,128,0.15)}",
    "@media(prefers-color-scheme:dark){:root{--mn-code-bg:rgba(255,255,255,0.09);--mn-inline-bg:rgba(255,255,255,0.09)}}",
  ].join("")
  document.head.appendChild(s)
})()

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
    s.className = "lp-checkbox" + (this.checked ? " lp-checkbox-checked" : "")
    return s
  }
}

// Normalize a GFM table so header/separator/data rows all share the same column count.
// Marked requires this; Obsidian is more lenient, so real-world tables may be mismatched.
function normalizeTableMd(tableMd) {
  const lines = tableMd.trim().split('\n')
  if (lines.length < 2) return tableMd
  const isSep = l => /^\|[\s|:-]+\|$/.test(l.trim())
  const sepIdx = lines.findIndex(isSep)
  if (sepIdx < 0) return tableMd
  const countCols = l => l.split('|').length - 2
  const target = Math.max(...lines.map(countCols))
  if (target < 1) return tableMd
  return lines.map((line, i) => {
    const cells = line.split('|').slice(1, -1)
    while (cells.length < target) cells.push(i === sepIdx ? '---' : '   ')
    return '|' + cells.slice(0, target).join('|') + '|'
  }).join('\n')
}

// Parse each table cell's source position for editable mapping.
function parseTableCells(state, tableFrom, tableTo) {
  const docLen = state.doc.length
  const rows = []
  let linePos = tableFrom
  while (linePos <= Math.min(tableTo, docLen - 1)) {
    const ln = state.doc.lineAt(linePos)
    const lineText = state.doc.sliceString(ln.from, Math.min(ln.to, docLen))
    const isSeparator = /^\s*\|[\s|:-]+\|\s*$/.test(lineText)
    if (isSeparator) {
      rows.push({ isSeparator: true, cells: [] })
    } else {
      const cells = []
      const pipes = []
      for (let i = 0; i < lineText.length; i++) {
        if (lineText[i] === '|') pipes.push(i)
      }
      for (let i = 0; i + 1 < pipes.length; i++) {
        const start = pipes[i] + 1
        const end   = pipes[i + 1]
        cells.push({ from: ln.from + start, to: ln.from + end, text: lineText.slice(start, end).trim() })
      }
      rows.push({ isSeparator: false, cells })
    }
    if (ln.from >= Math.min(tableTo, docLen - 1)) break
    linePos = ln.to + 1
  }
  return rows
}

class TableWidget extends WidgetType {
  constructor(html, rows) { super(); this.html = html; this.rows = rows }
  eq(o) { return this.html === o.html }
  ignoreEvent() { return true }  // let contenteditable handle all events
  toDOM(view) {
    const wrap = document.createElement("div")
    wrap.className = "lp-table-wrap"
    wrap.innerHTML = this.html

    const pending = {}  // from → { to, insert }

    const domTrs = [...wrap.querySelectorAll("tr")]
    let dataIdx = 0
    domTrs.forEach(domTr => {
      while (dataIdx < this.rows.length && this.rows[dataIdx].isSeparator) dataIdx++
      const rowData = this.rows[dataIdx]
      if (!rowData) { dataIdx++; return }
      ;[...domTr.querySelectorAll("th, td")].forEach((domCell, col) => {
        const cd = rowData.cells[col]
        if (!cd) return
        // Show rendered markdown when not focused; plain source when focused
        domCell.innerHTML = marked.parseInline(cd.text)
        domCell.contentEditable = "true"
        domCell.spellcheck = false
        domCell.style.cssText += ";outline:none;cursor:text"

        domCell.addEventListener("focus", () => {
          // Switch to plain markdown for editing
          domCell.textContent = cd.text
          selectAllInEl(domCell)
        })

        domCell.addEventListener("keydown", e => {
          if (e.key === "Tab") {
            e.preventDefault()
            const all = [...wrap.querySelectorAll("[contenteditable='true']")]
            const i = all.indexOf(domCell)
            const next = e.shiftKey ? all[i - 1] : all[i + 1]
            if (next) { next.focus(); selectAllInEl(next) }
          } else if (e.key === "Enter" || e.key === "Escape") {
            e.preventDefault()
            if (e.key === "Escape") domCell.blur()
          }
        })

        domCell.addEventListener("blur", () => {
          const newText = domCell.innerText.replace(/\n/g, " ")
          pending[cd.from] = { to: cd.to, insert: " " + newText + " " }
          // Restore rendered HTML
          domCell.innerHTML = marked.parseInline(newText || cd.text)
          // Dispatch only when focus fully leaves the table
          setTimeout(() => {
            if (wrap.contains(document.activeElement)) return
            const changes = Object.entries(pending)
              .map(([f, c]) => ({ from: +f, to: c.to, insert: c.insert }))
              .sort((a, b) => a.from - b.from)
              .filter(c => { try { return view.state.doc.sliceString(c.from, c.to) !== c.insert } catch { return false } })
            Object.keys(pending).forEach(k => delete pending[k])
            if (changes.length) view.dispatch({ changes })
          }, 0)
        })
      })
      dataIdx++
    })

    // Open links in cells without focusing the cell
    wrap.addEventListener("mousedown", e => {
      const a = e.target.closest("a[href]")
      if (a) { e.preventDefault(); openURL(a.getAttribute("href")) }
    })

    return wrap
  }
}

function selectAllInEl(el) {
  const r = document.createRange(); r.selectNodeContents(el)
  const s = window.getSelection(); s.removeAllRanges(); s.addRange(r)
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

        // ── List marks (bullet and ordered) ─────────────────────────────────
        if (name === "ListMark") {
          const parent = node.node.parent
          const grandparentName = parent?.parent?.name
          if (parent?.name === "ListItem") {
            const hasSpace = to < docLen && state.doc.sliceString(to, to + 1) === " "
            if (hasSpace) {
              if (grandparentName === "BulletList") {
                // Detect task list via raw text: "- [ ] " or "- [x] " after the ListMark
                const taskStart = to + 1  // character after the space that follows "-"
                const marker = taskStart + 3 <= docLen ? state.doc.sliceString(taskStart, taskStart + 3) : ""
                const isTask = marker === "[ ]" || /^\[x\]$/i.test(marker)
                if (isTask) {
                  const checked = /x/i.test(marker[1])
                  const trailingSpace = taskStart + 3 < docLen && state.doc.sliceString(taskStart + 3, taskStart + 4) === " "
                  addLine(from, "lp-task-line")
                  if (checked) addLine(from, "lp-task-done")
                  addWidget(from, taskStart + 3 + (trailingSpace ? 1 : 0), new CheckboxWidget(checked))
                } else {
                  addLine(from, "lp-bullet-line")
                  addWidget(from, to + 1, new BulletWidget())
                }
              } else if (grandparentName === "OrderedList") {
                addLine(from, "lp-ordered-line")
              }
            }
          }
          return false
        }

        // TaskMarker is handled inside the ListMark branch above

        // ── GFM Table ────────────────────────────────────────────────────────
        if (name === "Table") {
          try {
            const firstLine = state.doc.lineAt(from)
            // Don't trust lezer's `to` — scan lines explicitly.
            // A table row must start with '|'. Stop at the first non-table line.
            let lastLine = firstLine
            let scanPos = firstLine.to + 1
            while (scanPos < docLen) {
              const ln = state.doc.lineAt(scanPos)
              const text = state.doc.sliceString(ln.from, ln.to)
              if (!text.trimStart().startsWith('|')) break
              lastLine = ln
              scanPos = ln.to + 1
            }
            const tableMd = state.doc.sliceString(firstLine.from, lastLine.to)
            const html    = marked.parse(normalizeTableMd(tableMd))
            if (html.includes("<table")) {
              const rows = parseTableCells(state, firstLine.from, lastLine.to)
              // Replace first line with editable table widget (always rendered)
              addWidget(firstLine.from, firstLine.to, new TableWidget(html, rows))
              // Hide remaining table lines (rows 2..N)
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

// ─── Ordered list auto-renumber ───────────────────────────────────────────────

const renumberEffect = StateEffect.define()

function renumberOrderedLists(view) {
  const { state } = view
  const changes = []
  try {
    syntaxTree(state).iterate({
      enter(node) {
        if (node.name !== "OrderedList") return
        let expectedNum = 1
        let child = node.node.firstChild
        while (child) {
          if (child.name === "ListItem") {
            const mark = child.firstChild
            if (mark && mark.name === "ListMark") {
              const markText = state.doc.sliceString(mark.from, mark.to)
              const m = markText.match(/^(\d+)([.)])$/)
              if (m) {
                if (parseInt(m[1]) !== expectedNum) {
                  changes.push({ from: mark.from, to: mark.from + m[1].length, insert: String(expectedNum) })
                }
                expectedNum++
              }
            }
          }
          child = child.nextSibling
        }
        return false
      }
    })
  } catch (_) {}
  if (changes.length > 0) {
    view.dispatch({ changes, effects: renumberEffect.of(null) })
  }
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
        // Search the whole line for the TaskMarker (widget now covers "- [ ]" range)
        const line = view.state.doc.lineAt(pos)
        const tree = syntaxTree(view.state)
        let found = null
        tree.iterate({
          from: line.from,
          to: line.to,
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
    fontFamily: '"LXGW WenKai Medium", "LXGW WenKai", -apple-system, sans-serif',
    fontSize: "14px",
    lineHeight: "1.75",
    overflow: "auto",
  },
  ".cm-content": { padding: "18px 22px", minHeight: "100%", caretColor: "auto" },
  ".cm-line":    { padding: "1px 0" },
  ".cm-cursor":  { borderLeftWidth: "2px" },
  ".cm-focused": { outline: "none" },

  ".lp-h1": { fontSize: "1.9em",  fontWeight: "700", lineHeight: "1.3", paddingTop: "10px" },
  ".lp-h2": { fontSize: "1.55em", fontWeight: "700", lineHeight: "1.3", paddingTop: "8px" },
  ".lp-h3": { fontSize: "1.25em", fontWeight: "600", lineHeight: "1.3", paddingTop: "6px" },
  ".lp-h4": { fontSize: "1.1em",  fontWeight: "600", paddingTop: "6px" },
  ".lp-h5": { fontSize: "1em",    fontWeight: "600", paddingTop: "6px" },
  ".lp-h6": { fontSize: "0.95em", fontWeight: "600", paddingTop: "6px" },

  ".lp-syntax-dim": { color: "#aaa", fontWeight: "400 !important" },
  ".lp-strong": { fontWeight: "700" },
  ".lp-em":     { fontStyle: "italic" },
  ".lp-code": {
    fontFamily: '"Maple Mono NF CN", "SF Mono", monospace',
    fontSize: "0.88em",
    background: "var(--mn-inline-bg)",
    borderRadius: "3px",
    padding: "1px 4px",
  },
  ".lp-fenced-line": {
    fontFamily: '"Maple Mono NF CN", "SF Mono", monospace',
    fontSize: "0.88em",
    background: "var(--mn-code-bg)",
  },
  ".lp-link": {
    color: "#4a7cf7",
    textDecoration: "underline",
    cursor: "pointer",
  },
  ".lp-bullet": {
    display: "inline",
    userSelect: "none",
  },
  ".lp-bullet-line": {
    paddingLeft: "1.5em",
    textIndent: "-1.5em",
  },
  ".lp-ordered-line": {
    paddingLeft: "1.5em",
    textIndent: "-1.5em",
  },
  ".lp-checkbox": {
    display: "inline-block",
    width: "1em",
    height: "1em",
    border: "1.5px solid rgba(128,128,128,0.5)",
    borderRadius: "3px",
    boxSizing: "border-box",
    verticalAlign: "middle",
    marginRight: "0.35em",
    cursor: "pointer",
    userSelect: "none",
  },
  ".lp-checkbox-checked": {
    background: "#7c3aed",
    borderColor: "#7c3aed",
    backgroundImage: "url(\"data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'><path d='M1.5 5l2.5 2.5 4.5-4' stroke='white' stroke-width='1.5' fill='none' stroke-linecap='round' stroke-linejoin='round'/></svg>\")",
    backgroundRepeat: "no-repeat",
    backgroundPosition: "center",
    backgroundSize: "80%",
  },
  ".lp-task-line": {
    paddingLeft: "1.5em",
    textIndent: "-1.5em",
  },
  ".lp-task-done": {
    textDecoration: "line-through",
  },
  ".lp-task-done .lp-checkbox": {
    textDecoration: "none",
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
    maxWidth: "100%",
    overflowX: "auto",
    // Isolate table overflow so only the table scrolls, not the page
    contain: "inline-size",
  },
  ".lp-table-wrap table": {
    borderCollapse: "collapse",
    fontSize: "14px",
    lineHeight: "1.6",
    width: "max-content",  // natural column widths; wrapper scrolls when wider than panel
    minWidth: "0",
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
    markdown({ base: markdownLanguage, codeLanguages: languages }),
    highlightCompartment.of(currentHighlightExt()),
    EditorView.lineWrapping,
    livePreviewPlugin,
    interactionHandlers,
    editorTheme,
    EditorView.updateListener.of((update) => {
      if (!update.docChanged) return
      const isRenumber = update.transactions.some(tr => tr.effects.some(e => e.is(renumberEffect)))
      if (!isRenumber) renumberOrderedLists(update.view)
      if (_onChange) _onChange(update.view.state.doc.toString())
    }),
  ]
}

function makeView(content, parent) {
  return new EditorView({
    state: EditorState.create({ doc: content, extensions: buildExtensions() }),
    parent,
  })
}

// Reconfigure highlight theme when the OS appearance changes
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
  if (_view) {
    _view.dispatch({ effects: highlightCompartment.reconfigure(currentHighlightExt()) })
  }
})

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
