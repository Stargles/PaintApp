#!/bin/bash
# Samples the REAL memory of a simulator's render server and of the app, once a second, until killed.
#
#   tools/sim-footprint-sampler.sh <simulator-udid> <out.csv> [app-process-name]
#
# Each line: epoch,backboardd_MiB,backboardd_peak_MiB,app_MiB,app_peak_MiB
# (phys_footprint and phys_footprint_peak from `footprint`, the number jetsam kills on; an app column is
# blank while the app is not running). The simulated `backboardd` is an ordinary Mac process, found by
# the SIMULATOR_UDID in its environment, and the app is the process of that name under the same
# `launchd_sim`. `phys_footprint_peak` is the kernel's own high-water mark, so a spike between two
# samples is still seen. See tools/playcheck.sh, which runs the install gate around this.
set -u
UDID=$1; OUT=$2; APP=${3:-PaintSoftware}

backboardd_pid() {
    local p
    for p in $(pgrep -x backboardd); do
        if ps -E -o command= -p "$p" 2>/dev/null | tr ' ' '\n' | grep -qx "SIMULATOR_UDID=$UDID"; then
            echo "$p"; return
        fi
    done
}

# phys_footprint and its peak, in MiB, or ",".
mib() {
    footprint -f bytes --noCategories -p "$1" 2>/dev/null | awk '
        /phys_footprint:/ { now = $2 } /phys_footprint_peak:/ { peak = $2 }
        END { if (now != "") printf "%.1f,%.1f", now / 1048576, peak / 1048576; else printf "," }'
}

BBD=""
for _ in $(seq 60); do BBD=$(backboardd_pid); [[ -n "$BBD" ]] && break; sleep 1; done
[[ -n "$BBD" ]] || { echo "sim-footprint-sampler: no backboardd for $UDID — is the simulator booted?" >&2; exit 1; }
LAUNCHD=$(ps -o ppid= -p "$BBD" | tr -d ' ')
echo "epoch,backboardd_MiB,backboardd_peak_MiB,app_MiB,app_peak_MiB" > "$OUT"
while kill -0 "$BBD" 2>/dev/null; do
    APP_PID=$(pgrep -P "$LAUNCHD" -x "$APP" | head -1)
    echo "$(date +%s),$(mib "$BBD"),$([[ -n "$APP_PID" ]] && mib "$APP_PID" || printf ",")" >> "$OUT"
    sleep 1
done
echo "sim-footprint-sampler: backboardd $BBD exited" >&2
