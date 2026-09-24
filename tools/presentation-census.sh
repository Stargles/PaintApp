#!/bin/bash
# The thirty-second check behind MENU_PRESENTATION_CENSUS.md.
#
# Every dismissible presentation in this app is one of three things:
#
#   1. declared through `View.canvasPresentation` (or its drawing-less twin), with a case in
#      `CanvasPresentation` — drawn in the app's own hierarchy as an `AnchoredMenu`, safe;
#   2. a `.popover`, anywhere — this script FAILS on one. A UIKit popover over the canvas is torn
#      down under a live two-finger gesture and strands the canvas recognizers (TODO (110));
#   3. a `Menu` / `.contextMenu` / `ShareLink`, which UIKit presents itself — listed here so the
#      count stays honest.
#
# `CanvasPresentationLogicTests.testNoPopoverIsDeclaredAnywhereInTheApp` is case 2 again as a real
# gate: it runs in the fast tier whether or not anybody remembers this script. This stays because it
# answers in a second, from a shell, with no simulator.
#
# Usage: tools/presentation-census.sh          (from the repo root or anywhere inside it)

set -u
cd "$(dirname "$0")/.." || exit 2
app=PaintSoftware

# Skips comment lines: two doc comments quote `.popover(isPresented:)` while explaining this very
# rule, and a checker that flagged its own explanation would be uninhabitable.
code_grep() { grep -rnE "$1" --include=*.swift "$app" | grep -vE ':[0-9]+:[[:space:]]*(//|\*)'; }

echo "== 1. .popover anywhere in the app =="
bare=$(code_grep '\.popover\(')
if [ -n "$bare" ]; then
    echo "$bare"
    echo
    echo "FAIL: a UIKit popover over the canvas strands pan/pinch/rotation when it goes away under a"
    echo "two-finger gesture. Declare it with .canvasPresentation(_:isPresented:canvasManager:) and add"
    echo "a case to CanvasPresentation."
    exit 1
fi
echo "none — every presentation over the canvas is an AnchoredMenu."

echo
echo "== 2. Registered presentations =="
# Anchored to the start of the line, so the several doc comments naming the modifiers do not count as
# uses of them. Two modifiers: `canvasPresentation` hands its content to the editor's host, and
# `canvasPresentationRegistration` registers a menu the timeline draws itself. Both register into
# `CanvasManager.openPresentations` and both are closed by `AnchoredMenuRouter`.
sites=$(grep -rncE '^[[:space:]]*\.canvasPresentation(Registration)?\(' --include='*.swift' "$app" | grep -v ':0$')
cases=$(grep -cE '^    case [a-z]' $app/Models/CanvasPresentation.swift)
echo "$sites"
echo "$(echo "$sites" | awk -F: '{n += $2} END {print n}') call sites, $cases cases in CanvasPresentation."

echo
echo "== 3. Presentations with no binding to register — MENU_PRESENTATION_CENSUS.md's 12 =="
# The gallery screen mounts no canvas (ContentView is a `switch screen`), so its menus are not in the
# census's twelve and are excluded here for the same reason.
unbindable=$(code_grep '(^|[^A-Za-z0-9_])Menu \{|\.contextMenu|ShareLink\(' \
             | grep -v "^$app/Views/Gallery")
echo "$unbindable"
echo
echo "$(echo "$unbindable" | grep -c .) sites found. The census counts 12: its twelfth is the nested"
echo "Picker inside MotionGroupRow's .contextMenu, a submenu of a site already listed above."
echo "See MENU_PRESENTATION_CENSUS.md for what a stroke under each of these actually does."
