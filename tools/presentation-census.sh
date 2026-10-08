#!/bin/bash
# The thirty-second check behind MENU_PRESENTATION_CENSUS.md.
#
# Every presentation over the canvas is drawn by the app, in its own hierarchy, as an `AnchoredMenu`:
#
#   1. declared through `View.canvasPresentation` (a colour picker, a list, a panel), or through
#      `CanvasMenu` / `canvasContextMenu` (a menu), with a case in `CanvasPresentation` — drawn by
#      `canvasPresentationHost`, or by `AnimationTimeline`'s layer, and closed by `AnchoredMenuRouter`;
#   2. never a `.popover`, which this script FAILS on: a UIKit popover over the canvas is torn down
#      under a live two-finger gesture and strands the canvas recognizers (TODO (110));
#   3. never a SwiftUI `Menu`, `.contextMenu` or `.confirmationDialog`, which this script FAILS on
#      outside the gallery: UIKit tears them down under the touch that closes them, and the teardown
#      cancels the stroke that touch began.
#
# `CanvasPresentationLogicTests.testNoPopoverIsDeclaredAnywhereInTheApp` and
# `testNoSystemMenuIsDeclaredOverTheCanvas` are cases 2 and 3 again as real gates: they run in the fast
# tier whether or not anybody remembers this script. This stays because it answers in a second, from a
# shell, with no simulator.
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
echo "== 3. SwiftUI Menu, .contextMenu, .confirmationDialog anywhere over the canvas =="
# The gallery is a different screen (ContentView is a `switch screen`), so no canvas exists for a menu
# there to cancel a stroke on; its menus are exempt for that reason and no other.
menus=$(code_grep '(^|[^A-Za-z0-9_.])Menu[[:space:]]*[({]|\.contextMenu\b|\.confirmationDialog\b|\.pickerStyle\(\.menu\)' \
        | grep -v "^$app/Views/Gallery")
if [ -n "$menus" ]; then
    echo "$menus"
    echo
    echo "FAIL: a system menu over the canvas is torn down by UIKit under the touch that closes it, which"
    echo "cancels the stroke that touch began. Use CanvasMenu (tap to open) or .canvasContextMenu (press"
    echo "and hold) with a case in CanvasPresentation."
    exit 1
fi
echo "none — every menu over the canvas is a CanvasMenu or a canvasContextMenu."

echo
echo "== 4. Menus declared =="
echo "$(code_grep '(^|[^A-Za-z0-9_.])CanvasMenu\(' | wc -l | tr -d ' ') CanvasMenu, $(code_grep '\.canvasContextMenu\(' | wc -l | tr -d ' ') canvasContextMenu."

echo
echo "== 5. UIKit presentations that remain =="
# Not menus, and modal rather than anchored: the system share sheet. Listed so the count stays honest.
echo "$(code_grep 'ShareLink\(')"
