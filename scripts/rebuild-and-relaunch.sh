#!/bin/bash
# Stop hook: runs once when Claude finishes responding.
# Builds only if Swift or JS files were marked dirty this turn.

DIRTY_FILE="/tmp/mininotes-dirty-files"

if [ ! -f "$DIRTY_FILE" ]; then
  exit 0
fi

CHANGED=$(cat "$DIRTY_FILE")
rm -f "$DIRTY_FILE"

PROJECT_DIR="/Users/pingfan/Documents/GitHub/software/MiniNotes"
APP_PATH="/Users/pingfan/Library/Developer/Xcode/DerivedData/MiniNotes-dqmwdyrthfgyezeddoegrwdqawje/Build/Products/Debug/MiniNotes.app"

echo "==> Building MiniNotes..."

if echo "$CHANGED" | grep -q "editor.js"; then
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
