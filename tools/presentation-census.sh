#!/bin/bash
# The thirty-second check behind MENU_PRESENTATION_CENSUS.md.
#
# Every dismissible presentation in this app is one of three things:
#
#   1. declared through `View.canvasPresentation`, with a case in `CanvasPresentation` — safe;
#   2. a bare `.popover`, which is the defect the census counted seven times — this script FAILS on one;
#   3. a `Menu` / `.contextMenu` / stock `ColorPicker` / `ShareLink`, which expose no `isPresented`
#      binding and so cannot be registered at all — listed here so the count stays honest.
#
# `CanvasPresentationLogicTests.testNoBarePopoverIsDeclaredOutsideTheModifier` is case 2 again as a
# real gate: it runs in the fast tier whether or not anybody remembers this script. This stays because
# it answers in a second, from a shell, with no simulator.
#
# Usage: tools/presentation-census.sh          (from the repo root or anywhere inside it)

set -u
cd "$(dirname "$0")/.." || exit 2
app=PaintSoftware
modifier=$app/Views/CanvasPresentationModifier.swift

# Skips comment lines: two doc comments quote `.popover(isPresented:)` while explaining this very
# rule, and a checker that flagged its own explanation would be uninhabitable.
code_grep() { grep -rnE "$1" --include=*.swift "$app" | grep -vE ':[0-9]+:[[:space:]]*(//|\*)'; }

echo "== 1. Bare .popover outside $modifier =="
bare=$(code_grep '\.popover\(' | grep -v "^$modifier:")
if [ -n "$bare" ]; then
    echo "$bare"
    echo
    echo "FAIL: a .popover declared outside the modifier is unregistered, so a canvas touch tears it"
    echo "down mid-stroke. Declare it with .canvasPresentation(_:isPresented:canvasManager:) and add a"
    echo "case to CanvasPresentation — including when the answer is overlapsLiveCanvas == false."
    exit 1
fi
echo "none — every popover in the app goes through the modifier."

echo
echo "== 2. Registered presentations =="
# Anchored to the start of the line, so the several doc comments naming the modifier do not count as
# uses of it.
sites=$(grep -rncE '^[[:space:]]*\.canvasPresentation\(' --include='*.swift' "$app" | grep -v ':0$')
cases=$(grep -cE '^    case [a-z]' $app/Models/CanvasPresentation.swift)
echo "$sites"
echo "$(echo "$sites" | awk -F: '{n += $2} END {print n}') call sites, $cases cases in CanvasPresentation" \
     "(8 over a live canvas + 2 on the gallery screen, which registers nothing)."

echo
echo "== 3. Presentations with no binding to register — MENU_PRESENTATION_CENSUS.md's 12 =="
# The gallery screen mounts no canvas (ContentView is a `switch screen`), so its menus are not in the
# census's twelve and are excluded here for the same reason.
unbindable=$(code_grep '(^|[^A-Za-z0-9_])Menu \{|\.contextMenu|ColorPicker\(|ShareLink\(' \
             | grep -v "^$app/Views/Gallery")
echo "$unbindable"
echo
echo "$(echo "$unbindable" | grep -c .) sites found. The census counts 12: its twelfth is the nested"
echo "Picker inside MotionGroupRow's .contextMenu, a submenu of a site already listed above."
echo "See MENU_PRESENTATION_CENSUS.md for what a stroke under each of these actually does."
