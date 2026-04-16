#!/bin/bash
# PostToolUse: records which Swift/JS files were edited this turn.
# The actual build is deferred to the Stop hook.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

case "$FILE" in
  *.swift|*/build/src/editor.js) ;;
  *) exit 0 ;;
esac

echo "$FILE" >> /tmp/mininotes-dirty-files
