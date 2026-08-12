// Smart toggle commands for inline formatting: bold (Mod-b), italic (Mod-i).
//
// Detection is syntax-tree based, so toggling tolerates selections that
// include or exclude the surrounding markers, carets placed anywhere inside
// a styled span, and mixed nesting like ***bold italic***.

import { ensureSyntaxTree, syntaxTree } from "@codemirror/language"
import { EditorSelection } from "@codemirror/state"

// syntaxTree() may be a partial parse in headless contexts; force a full one.
function fullTree(state) {
  return ensureSyntaxTree(state, state.doc.length, 5000) || syntaxTree(state)
}

function trimmedRange(state, from, to) {
  const text = state.sliceDoc(from, to)
  const lead = text.length - text.trimStart().length
  const trail = text.length - text.trimEnd().length
  return { from: from + lead, to: to - trail }
}

// Find a node named `name` that either encloses [from, to] or exactly spans
// the whitespace-trimmed selection (the user selected the markers too).
function findStyledNode(state, name, from, to) {
  const tree = fullTree(state)
  const trimmed = trimmedRange(state, from, to)
  const seen = new Set()
  const probes = [
    [from, 1], [from, -1], [to, 1], [to, -1],
    // Selection may include whitespace around the styled span; probe the
    // trimmed edges too so the enclosing node is still found.
    [trimmed.from, 1], [trimmed.to, -1],
  ]
  for (const [pos, side] of probes) {
    if (pos < 0 || pos > state.doc.length) continue
    for (let n = tree.resolveInner(pos, side); n; n = n.parent) {
      if (n.name !== name) continue
      const key = n.from + ":" + n.to
      if (seen.has(key)) continue
      seen.add(key)
      const encloses = n.from <= from && n.to >= to
      const exact = n.from === trimmed.from && n.to === trimmed.to
      if (encloses || exact) return n
    }
  }
  return null
}

// Remove a styled node's delimiters (first and last mark child).
function unwrapNode(state, dispatch, node, markName) {
  const marks = []
  for (let c = node.firstChild; c; c = c.nextSibling) {
    if (c.name === markName) marks.push([c.from, c.to])
  }
  if (marks.length < 2) return false
  const open = marks[0]
  const close = marks[marks.length - 1]
  dispatch(state.update({
    changes: [{ from: open[0], to: open[1] }, { from: close[0], to: close[1] }],
    userEvent: "delete.format",
  }))
  return true
}

// Wrap the selection (or the word under an empty cursor) in open/close markers.
function wrapRange(state, dispatch, open, close) {
  const range = state.selection.main
  let { from, to } = range
  if (range.empty) {
    const word = state.wordAt(from)
    if (word) {
      from = word.from
      to = word.to
    } else {
      // Caret already inside an empty pair (e.g. from a previous toggle):
      // toggle it off instead of stacking another pair
      const before = state.sliceDoc(Math.max(0, from - open.length), from)
      const after = state.sliceDoc(to, Math.min(state.doc.length, to + close.length))
      if (before === open && after === close) {
        dispatch(state.update({
          changes: [
            { from: from - open.length, to: from },
            { from: to, to: to + close.length },
          ],
          userEvent: "delete.format",
        }))
        return true
      }
      // Not on a word: insert an empty pair with the caret inside
      dispatch(state.update({
        changes: { from, insert: open + close },
        selection: EditorSelection.cursor(from + open.length),
        userEvent: "input.format",
      }))
      return true
    }
  } else {
    // Keep whitespace at the selection edges outside the markers
    const t = trimmedRange(state, from, to)
    from = t.from
    to = t.to
    if (from >= to) {
      // Whitespace-only selection: behave like an empty caret at its start
      dispatch(state.update({
        changes: { from: range.from, insert: open + close },
        selection: EditorSelection.cursor(range.from + open.length),
        userEvent: "input.format",
      }))
      return true
    }
  }
  dispatch(state.update({
    changes: [{ from, insert: open }, { from: to, insert: close }],
    selection: range.empty
      ? EditorSelection.cursor(range.from + open.length)
      : EditorSelection.range(from + open.length, to + open.length),
    userEvent: "input.format",
  }))
  return true
}

// ── Star-run ("cluster") handling ───────────────────────────────────────────
// With the caret anywhere inside `stars + text + stars` — including the
// outermost edges — ⌘B/⌘I act on the whole construct as if its text were
// selected. Count-based, not parse-based, so it stays correct even for runs
// the Markdown parser can't classify (e.g. ****aa***), and such malformed
// runs are repaired first: balanced sides, at most 3 stars each.

const MAX_MARKS = 3

function findStarCluster(state, from, to) {
  const line = state.doc.lineAt(from)
  if (to > line.to) return null
  const re = /(\*+)([^*]+)(\*+)/g
  let m
  while ((m = re.exec(line.text)) !== null) {
    const s = line.from + m.index
    const e = s + m[0].length
    if (s <= from && to <= e) return { s, e, left: m[1].length, right: m[3].length }
    if (s > to) break
  }
  return null
}

function rewriteCluster(state, dispatch, cluster, n) {
  dispatch(state.update({
    changes: [
      { from: cluster.s, to: cluster.s + cluster.left, insert: "*".repeat(n) },
      { from: cluster.e - cluster.right, to: cluster.e, insert: "*".repeat(n) },
    ],
    userEvent: "input.format",
  }))
  return true
}

function toggleEmphasis(nodeName, bit, marker) {
  return ({ state, dispatch }) => {
    if (state.readOnly) return false
    const { from, to } = state.selection.main
    if (from === to) {
      const cluster = findStarCluster(state, from, to)
      if (cluster) {
        const { left, right } = cluster
        const n = Math.min(MAX_MARKS, left, right)
        // Malformed run (unequal sides or >3 stars): this press repairs it
        if (left !== right || left > MAX_MARKS || right > MAX_MARKS) {
          return rewriteCluster(state, dispatch, cluster, n)
        }
        // Well-formed: prefer the semantic tree unwrap (handles nesting
        // context); fall back to rewriting the run by its style bits
        // (1 = italic, 2 = bold, 3 = both).
        const node = findStyledNode(state, nodeName, from, to)
        if (node && unwrapNode(state, dispatch, node, "EmphasisMark")) return true
        return rewriteCluster(state, dispatch, cluster, n ^ bit)
      }
    }
    const node = findStyledNode(state, nodeName, from, to)
    if (node) return unwrapNode(state, dispatch, node, "EmphasisMark")
    return wrapRange(state, dispatch, marker, marker)
  }
}

export const toggleBold = toggleEmphasis("StrongEmphasis", 2, "**")
export const toggleItalic = toggleEmphasis("Emphasis", 1, "*")

// preventDefault even when a command declines (e.g. read-only view mode), so
// WebKit's native rich-text handlers (toggleBold: etc.) never fire on the
// contenteditable editor.
export const formattingKeymap = [
  { key: "Mod-b", run: toggleBold, preventDefault: true },
  { key: "Mod-i", run: toggleItalic, preventDefault: true },
]
