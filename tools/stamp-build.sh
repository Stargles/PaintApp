#!/bin/bash
# Build phase: stamps the built Info.plist with the commit and time this binary was built from.
# Writes only into the built product, never a tracked file. CFBundleVersion = commit count (monotonic).
set -u
PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
[ -f "$PLIST" ] || { echo "stamp-build: no $PLIST"; exit 1; }
cd "$SRCROOT" || exit 1
SHA=$(git rev-parse --short=8 HEAD 2>/dev/null || echo unknown)
COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 1)
DIRTY=""
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then DIRTY="+"; fi
WHEN=$(LC_ALL=C date "+%b %-d %H:%M")
LABEL="Build ${SHA}${DIRTY} · ${WHEN}"
PB=/usr/libexec/PlistBuddy
set_key() { "$PB" -c "Set :$1 $2" "$PLIST" 2>/dev/null || "$PB" -c "Add :$1 string $2" "$PLIST"; }
set_key CFBundleVersion "$COUNT"
set_key PaintBuildCommit "${SHA}${DIRTY}"
"$PB" -c "Delete :PaintBuildLabel" "$PLIST" 2>/dev/null
"$PB" -c "Add :PaintBuildLabel string $LABEL" "$PLIST"
echo "stamp-build: $LABEL (CFBundleVersion $COUNT)"
