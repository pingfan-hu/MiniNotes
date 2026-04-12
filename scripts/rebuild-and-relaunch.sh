#!/bin/bash
# Rebuild MiniNotes and relaunch after file edits.
# Reads Claude Code PostToolUse JSON from stdin and only acts on .swift / editor.js files.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Only rebuild for Swift source files or the JS editor source
case "$FILE" in
  *.swift|*/build/src/editor.js) ;;
  *) exit 0 ;;
esac

PROJECT_DIR="/Users/pingfan/Documents/GitHub/software/MiniNotes"
APP_PATH="/Users/pingfan/Library/Developer/Xcode/DerivedData/MiniNotes-dqmwdyrthfgyezeddoegrwdqawje/Build/Products/Debug/MiniNotes.app"

echo "==> Building MiniNotes (changed: $FILE)..."

# If the changed file is editor.js, also bundle it first
if [[ "$FILE" == */build/src/editor.js ]]; then
  cd "$PROJECT_DIR/build" && npm run build --silent
fi

cd "$PROJECT_DIR"
xcodebuild \
  -project MiniNotes.xcodeproj \
  -scheme MiniNotes \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build -quiet 2>&1 | tail -5

pkill -x MiniNotes 2>/dev/null || true
sleep 0.3
open "$APP_PATH"
echo "==> MiniNotes relaunched."
