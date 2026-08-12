// List indentation (Tab / Shift-Tab) and ordered-list renumbering.
//
// Obsidian-style: Tab with the caret anywhere on a list line (bullet,
// ordered, or task) indents the whole item one level by inserting a tab at
// line start; Shift-Tab removes one leading tab (or up to 4 leading spaces).
// Range selections indent/outdent every list line they touch. Outside
// lists, Tab inserts a literal tab character.

import { ensureSyntaxTree, syntaxTree } from "@codemirror/language"

const LIST_LINE_RE = /^[\t ]*(?:[-*+]|\d+[.)])(?: |$)/

// syntaxTree() may be a partial parse in headless contexts; force a full one.
function fullTree(state) {
  return ensureSyntaxTree(state, state.doc.length, 5000) || syntaxTree(state)
}

function selectedLines(state) {
  const lines = []
  const seen = new Set()
  for (const r of state.selection.ranges) {
    const end = state.doc.lineAt(r.to).number
    for (let n = state.doc.lineAt(r.from).number; n <= end; n++) {
      if (!seen.has(n)) { seen.add(n); lines.push(state.doc.line(n)) }
    }
  }
  return lines
}

export function indentListItem({ state, dispatch }) {
  if (state.readOnly) return false
  const listLines = selectedLines(state).filter(l => LIST_LINE_RE.test(l.text))
  if (listLines.length) {
    const changes = state.changes(listLines.map(l => ({ from: l.from, insert: "\t" })))
    dispatch(state.update({
      changes,
      // assoc 1: a caret sitting exactly at line start stays with the text
      // (after the inserted tab), not before it
      selection: state.selection.map(changes, 1),
      userEvent: "input.indent",
    }))
    return true
  }
  // Not in a list: insert a literal tab (replacing any selection)
  dispatch(state.update(state.replaceSelection("\t"), { userEvent: "input" }))
  return true
}

export function outdentListItem({ state, dispatch }) {
  if (state.readOnly) return false
  const changes = []
  for (const l of selectedLines(state)) {
    if (!LIST_LINE_RE.test(l.text)) continue
    const m = l.text.match(/^(?:\t| {1,4})/)
    if (m) changes.push({ from: l.from, to: l.from + m[0].length })
  }
  if (!changes.length) return false
  dispatch(state.update({ changes, userEvent: "delete.dedent" }))
  return true
}

// Compute the changes that fix ordered-list numbering. Each OrderedList node
// is renumbered from 1 independently, so nested lists restart their count
// (Obsidian behavior).
export function orderedListRenumberChanges(state) {
  const changes = []
  try {
    fullTree(state).iterate({
      enter(node) {
        if (node.name !== "OrderedList") return
        let expectedNum = 1
        for (let child = node.node.firstChild; child; child = child.nextSibling) {
          if (child.name !== "ListItem") continue
          const mark = child.firstChild
          if (mark && mark.name === "ListMark") {
            const m = state.doc.sliceString(mark.from, mark.to).match(/^(\d+)[.)]$/)
            if (m) {
              if (parseInt(m[1]) !== expectedNum) {
                changes.push({ from: mark.from, to: mark.from + m[1].length, insert: String(expectedNum) })
              }
              expectedNum++
            }
          }
        }
        // No `return false`: descend into items so nested lists renumber too
      }
    })
  } catch (_) {}
  return changes
}

// preventDefault even when a command declines, so Tab never moves focus out
// of the editor.
export const listKeymap = [
  { key: "Tab", run: indentListItem, preventDefault: true },
  { key: "Shift-Tab", run: outdentListItem, preventDefault: true },
]
