// Headless test suite for the smart formatting toggles (Mod-b / Mod-i).
// Run: npm test   (from build/)
//
// Docs are written with "|" marking the selection anchor/head:
//   one "|"  → caret;  two "|" → selection between them.

import { EditorState, EditorSelection } from "@codemirror/state"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { Strikethrough } from "@lezer/markdown"
import { toggleBold, toggleItalic } from "../src/formatting.js"

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

function apply(command, spec) {
  const { doc, anchor, head } = parseSpec(spec)
  let state = EditorState.create({
    doc,
    selection: EditorSelection.single(anchor, head),
    extensions: [markdown({ base: markdownLanguage, extensions: [Strikethrough] })],
  })
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
    failures.push(`✗ ${label}\n    command returned false on: ${spec}`)
    return
  }
  if (result === expected) {
    pass++
    console.log(`✓ ${label}`)
  } else {
    fail++
    failures.push(`✗ ${label}\n    input:    ${spec}\n    expected: ${expected}\n    got:      ${result}`)
  }
}

// Round-trip: applying the command twice must return to the input text
// (selection may differ; only the document is asserted).
function checkRoundTrip(label, command, spec) {
  const { doc } = parseSpec(spec)
  const once = apply(command, spec)
  const twice = apply(command, once.result)
  const finalDoc = parseSpec(twice.result).doc
  if (finalDoc === doc) {
    pass++
    console.log(`✓ ${label} (round-trip)`)
  } else {
    fail++
    failures.push(`✗ ${label} (round-trip)\n    input doc: ${doc}\n    after 2x:  ${finalDoc}\n    (1x was:   ${once.result})`)
  }
}

// ── 1. Wrap: plain selection ────────────────────────────────────────────────
check("bold wraps selection", toggleBold, "say |hello| there", "say **|hello|** there")
check("italic wraps selection", toggleItalic, "say |hello| there", "say *|hello|* there")

// ── 2. Unwrap: selection = inner text only ──────────────────────────────────
check("bold unwrap, inner selected", toggleBold, "say **|hello|** there", "say |hello| there")
check("italic unwrap, inner selected", toggleItalic, "say *|hello|* there", "say |hello| there")

// ── 3. Unwrap: selection includes the markers ───────────────────────────────
check("bold unwrap, markers selected", toggleBold, "say |**hello**| there", "say |hello| there")
check("italic unwrap, markers selected", toggleItalic, "say |*hello*| there", "say |hello| there")

// ── 4. Unwrap: bare caret inside styled text ────────────────────────────────
check("bold unwrap, caret inside", toggleBold, "say **hel|lo** there", "say hel|lo there")
check("italic unwrap, caret inside", toggleItalic, "say *hel|lo* there", "say hel|lo there")
check("bold unwrap, caret just inside closing marks", toggleBold, "say **hello|** there", "say hello| there")

// ── 5. Mix-and-match combos ─────────────────────────────────────────────────
check("*** both: italic off keeps bold", toggleItalic, "a ***bo|th*** b", "a **bo|th** b")
check("*** both: bold off keeps italic", toggleBold, "a ***bo|th*** b", "a *bo|th* b")
check("bold inside italic sentence: bold off", toggleBold, "*see **bo|ld** here*", "*see bo|ld here*")
check("bold inside italic sentence: italic off", toggleItalic, "*see **bo|ld** here*", "see **bo|ld** here")

// ── 6. Stacking a second style, then round-tripping it off ──────────────────
check("italic added around bold word", toggleItalic, "say **|hello|** there", "say ***|hello|*** there")
checkRoundTrip("italic on/off around bold", toggleItalic, "say **|hello|** there")
check("bold added around italic word", toggleBold, "say *|hello|* there", "say ***|hello|*** there")
checkRoundTrip("bold on/off around italic", toggleBold, "say *|hello|* there")

// ── 7. No selection: caret in a word toggles the word ───────────────────────
check("bold word under caret", toggleBold, "say hel|lo there", "say **hel|lo** there")
check("italic word under caret", toggleItalic, "say hel|lo there", "say *hel|lo* there")

// ── 8. No selection, empty space: insert empty markers, caret inside ────────
check("bold empty markers on blank", toggleBold, "text |", "text **|**")
check("italic empty markers on blank", toggleItalic, "text |", "text *|*")

// ── 9. Partial-word wrap; whitespace-edged selections trimmed ───────────────
check("bold partial word", toggleBold, "in|tern|ational", "in**|tern|**ational")
check("bold trims edge whitespace", toggleBold, "say | hello | there", "say  **|hello|**  there")
check("italic trims edge whitespace", toggleItalic, "say |hello |there", "say *|hello|* there")

// ── 10. Idempotence / round-trips ───────────────────────────────────────────
checkRoundTrip("bold round-trip", toggleBold, "say |hello| there")
checkRoundTrip("italic round-trip", toggleItalic, "say |hello| there")
checkRoundTrip("bold word-under-caret round-trip", toggleBold, "say hel|lo there")
checkRoundTrip("italic word-under-caret round-trip", toggleItalic, "say hel|lo there")

// ── Extra tolerance cases ───────────────────────────────────────────────────
check("bold unwrap when selection has extra space", toggleBold, "say | **hello** | there", "say | hello | there")
check("multiple bolds: only enclosing one toggles", toggleBold, "**one** and **t|wo**", "**one** and t|wo")
check("bold multi-word selection", toggleBold, "|one two three|", "**|one two three|**")
check("bold unwrap multi-word", toggleBold, "**one t|wo three**", "one t|wo three")

console.log("")
for (const f of failures) console.error(f + "\n")
console.log(`${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
