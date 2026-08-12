// Headless test suite for list indentation (Tab / Shift-Tab) and
// ordered-list renumbering.
// Run: npm test   (from build/)
//
// Docs are written with "|" marking the selection anchor/head:
//   one "|"  → caret;  two "|" → selection between them.

import { EditorState, EditorSelection } from "@codemirror/state"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { indentListItem, outdentListItem, orderedListRenumberChanges } from "../src/lists.js"

function parseSpec(spec) {
  const first = spec.indexOf("|")
  const second = spec.indexOf("|", first + 1)
  if (first === -1) throw new Error("spec needs at least one |: " + spec)
  const doc = spec.replace(/\|/g, "")
  const anchor = first
  const head = second === -1 ? first : second - 1
  return { doc, anchor, head }
}

function renderSpec(doc, sel) {
  if (sel.empty) return doc.slice(0, sel.from) + "|" + doc.slice(sel.from)
  return doc.slice(0, sel.from) + "|" + doc.slice(sel.from, sel.to) + "|" + doc.slice(sel.to)
}

function makeState(spec) {
  const { doc, anchor, head } = parseSpec(spec)
  return EditorState.create({
    doc,
    selection: EditorSelection.single(anchor, head),
    extensions: [markdown({ base: markdownLanguage })],
  })
}

function apply(command, spec) {
  let state = makeState(spec)
  const handled = command({
    state,
    dispatch: (tr) => { state = tr.state },
  })
  return { handled, result: renderSpec(state.doc.toString(), state.selection.main) }
}

let pass = 0
let fail = 0
const failures = []

function check(label, command, spec, expected) {
  const { handled, result } = apply(command, spec)
  if (!handled) {
    fail++
    failures.push(`✗ ${label}\n    command returned false on: ${JSON.stringify(spec)}`)
    return
  }
  if (result === expected) {
    pass++
    console.log(`✓ ${label}`)
  } else {
    fail++
    failures.push(`✗ ${label}\n    input:    ${JSON.stringify(spec)}\n    expected: ${JSON.stringify(expected)}\n    got:      ${JSON.stringify(result)}`)
  }
}

function checkUnhandled(label, command, spec) {
  const { handled, result } = apply(command, spec)
  if (!handled && result === spec) {
    pass++
    console.log(`✓ ${label}`)
  } else {
    fail++
    failures.push(`✗ ${label}\n    expected unhandled/no-op on: ${JSON.stringify(spec)}\n    handled: ${handled}, got: ${JSON.stringify(result)}`)
  }
}

function checkRenumber(label, docText, expected) {
  let state = EditorState.create({
    doc: docText,
    extensions: [markdown({ base: markdownLanguage })],
  })
  const changes = orderedListRenumberChanges(state)
  const result = changes.length ? state.update({ changes }).state.doc.toString() : docText
  if (result === expected) {
    pass++
    console.log(`✓ ${label}`)
  } else {
    fail++
    failures.push(`✗ ${label}\n    input:    ${JSON.stringify(docText)}\n    expected: ${JSON.stringify(expected)}\n    got:      ${JSON.stringify(result)}`)
  }
}

// ── 1. Tab indents list items ───────────────────────────────────────────────
check("indent bullet, caret mid-text", indentListItem,
  "- aa\n- b|b", "- aa\n\t- b|b")
check("indent bullet, caret at line start", indentListItem,
  "- aa\n|- bb", "- aa\n\t|- bb")
check("indent ordered item", indentListItem,
  "1. aa\n2. b|b", "1. aa\n\t2. b|b")
check("indent task item", indentListItem,
  "- [ ] aa\n- [x] b|b", "- [ ] aa\n\t- [x] b|b")
check("indent already-nested item one more level", indentListItem,
  "- aa\n\t- b|b", "- aa\n\t\t- b|b")
check("indent multi-line selection hits every list line", indentListItem,
  "- a|a\n- bb\n- c|c", "\t- a|a\n\t- bb\n\t- c|c")
check("selection spanning list and plain lines indents only list lines", indentListItem,
  "- a|a\nplain\n- c|c", "\t- a|a\nplain\n\t- c|c")

// ── 2. Tab outside lists inserts a literal tab ──────────────────────────────
check("tab in plain text inserts tab char", indentListItem,
  "hello| world", "hello\t| world")
check("tab replaces plain-text selection", indentListItem,
  "a|bc|d", "a\t|d")

// ── 3. Shift-Tab outdents ───────────────────────────────────────────────────
check("outdent removes one leading tab", outdentListItem,
  "- aa\n\t- b|b", "- aa\n- b|b")
check("outdent removes only one tab of two", outdentListItem,
  "- aa\n\t\t- b|b", "- aa\n\t- b|b")
check("outdent removes up to 4 leading spaces", outdentListItem,
  "- aa\n    - b|b", "- aa\n- b|b")
check("outdent removes 2-space indent", outdentListItem,
  "- aa\n  - b|b", "- aa\n- b|b")
check("outdent multi-line selection", outdentListItem,
  "\t- a|a\n\t- b|b", "- a|a\n- b|b")
checkUnhandled("outdent at top level is a no-op", outdentListItem,
  "- a|a")
checkUnhandled("outdent on plain text is a no-op", outdentListItem,
  "plain te|xt")

// ── 4. Round trip ───────────────────────────────────────────────────────────
{
  const spec = "- aa\n- b|b"
  const once = apply(indentListItem, spec)
  const back = apply(outdentListItem, once.result)
  if (back.result === spec) {
    pass++
    console.log("✓ indent then outdent round-trips")
  } else {
    fail++
    failures.push(`✗ indent then outdent round-trips\n    expected: ${JSON.stringify(spec)}\n    got:      ${JSON.stringify(back.result)}`)
  }
}

// ── 5. Ordered-list renumbering (incl. nested) ──────────────────────────────
checkRenumber("renumbers flat list",
  "1. a\n3. b\n7. c", "1. a\n2. b\n3. c")
checkRenumber("nested list renumbers independently from 1",
  "1. a\n\t3. b\n\t5. c\n4. d", "1. a\n\t1. b\n\t2. c\n2. d")
checkRenumber("deeply nested list renumbers each level",
  "1. a\n\t1. b\n\t\t4. c\n\t\t9. d\n\t7. e", "1. a\n\t1. b\n\t\t1. c\n\t\t2. d\n\t2. e")
// Note: the nested list must start with "1." — CommonMark only lets an
// ordered list interrupt a paragraph when it starts at 1.
checkRenumber("ordered nested under bullet renumbers",
  "- a\n\t1. b\n\t5. c", "- a\n\t1. b\n\t2. c")
checkRenumber("correct lists produce no changes",
  "1. a\n2. b\n\t1. c\n\t2. d", "1. a\n2. b\n\t1. c\n\t2. d")

// ── Summary ─────────────────────────────────────────────────────────────────
console.log(`\n${pass} passed, ${fail} failed`)
if (failures.length) {
  console.log("\n" + failures.join("\n\n"))
  process.exit(1)
}
