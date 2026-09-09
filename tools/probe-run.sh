#!/bin/bash
# Runs `PlaybackProbe` on the owner's iPad and brings its JSON report back.
#
# The probe exits when it has written its report, so `--console` is the completion signal and this
# script is one blocking command rather than a poll — CLAUDE.md's rule about waiting.
#
#   tools/probe-run.sh <label> [extra probe args...]
#
# Everything after the label goes straight to the app, so the caller spells `-probeMode edit
# -probeWidth 2048 ...` itself and this file holds no defaults to go stale.
set -euo pipefail

DEVICE=E3B83820-DF74-5042-B52B-0D5BA17E4877
BUNDLE=Starg.PaintSoftware
LABEL="$1"; shift

OUT="${PROBE_OUT_DIR:-$(pwd)/probe-reports}"
mkdir -p "$OUT"

xcrun devicectl device process launch --device "$DEVICE" --terminate-existing --console \
  "$BUNDLE" -- -playbackProbe -probeLabel "$LABEL" "$@" 2>&1 | tail -5 || true

# `copy from` on the folder brings back everything, which is what a run wants: the report's own name
# carries a timestamp the caller does not know, and a stale one from an earlier run is harmless here
# because the caller reads by label and mtime.
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
  --domain-identifier "$BUNDLE" --source "Documents/Probe" --destination "$OUT" > /dev/null 2>&1

NEWEST=$(ls -t "$OUT"/playback-"$LABEL"-*.json 2>/dev/null | head -1)
if [ -z "$NEWEST" ]; then echo "NO REPORT for label $LABEL"; exit 1; fi
echo "REPORT: $NEWEST"
