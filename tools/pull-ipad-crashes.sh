#!/bin/bash
# Pulls what the iPad has recorded about crashes, when the owner asks for it (nothing runs this on its own).
#
#   tools/pull-ipad-crashes.sh [device-uuid]
#
# Copies to ~/PaintWork/ipad-crashes/, skipping files already there:
#   system/   JetsamEvent-*.ips and PaintSoftware* crash/resource logs   (systemCrashLogs domain)
#   app/      the app's own crash-*, metrickit-* and flight-* recordings  (Starg.PaintSoftware, Documents/Recordings)
# then prints one line per new Jetsam event: who the system killed and which process was largest.
# Never waits on the device: refuses unless `devicectl list devices` says it is available, and bounds each call.
set -u
DEVICE="${1:-E3B83820-DF74-5042-B52B-0D5BA17E4877}"
BUNDLE="Starg.PaintSoftware"
OUT="${PAINT_CRASH_DIR:-$HOME/PaintWork/ipad-crashes}"
mkdir -p "$OUT/system" "$OUT/app"

if ! xcrun devicectl list devices 2>/dev/null | grep -F "$DEVICE" | grep -q "available"; then
  echo "iPad $DEVICE is not available (asleep, locked or off the network) - nothing pulled."
  exit 1
fi

export DEVICE BUNDLE OUT
exec python3 -I - <<'PY'
import json, os, subprocess, sys, tempfile

DEVICE, BUNDLE, OUT = os.environ["DEVICE"], os.environ["BUNDLE"], os.environ["OUT"]

def devicectl(*args, timeout=120):
    return subprocess.run(["xcrun", "devicectl", *args], capture_output=True, text=True, timeout=timeout)

def listing(domain, identifier=None):
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "list.json")
        cmd = ["device", "info", "files", "--device", DEVICE, "--domain-type", domain, "--json-output", path]
        if identifier: cmd += ["--domain-identifier", identifier]
        try:
            r = devicectl(*cmd, timeout=60)
            return [f for f in json.load(open(path))["result"]["files"] if not f["resources"]["isDirectory"]]
        except Exception as e:
            print(f"could not list {domain}: {e}", file=sys.stderr)
            return []

def pull(domain, identifier, rel, dest):
    full = ["device", "copy", "from", "--device", DEVICE, "--domain-type", domain]
    if identifier: full += ["--domain-identifier", identifier]
    full += ["--source", rel, "--destination", dest]
    try:
        return devicectl(*full, timeout=180).returncode == 0
    except subprocess.TimeoutExpired:
        return False

new = {"system": [], "app": []}

for f in listing("systemCrashLogs"):
    name = f["relativePath"]
    if not (name.startswith("JetsamEvent-") or name.startswith("PaintSoftware")): continue
    dest = os.path.join(OUT, "system", name.replace("/", "_"))
    if os.path.exists(dest): continue
    if pull("systemCrashLogs", None, name, dest): new["system"].append(dest)

for f in listing("appDataContainer", BUNDLE):
    rel = f["relativePath"]
    if not rel.startswith("Documents/Recordings/"): continue
    name = os.path.basename(rel)
    if not name.startswith(("crash-", "metrickit-", "flight-")): continue
    dest = os.path.join(OUT, "app", name)
    if os.path.exists(dest): continue
    if pull("appDataContainer", BUNDLE, rel, dest): new["app"].append(dest)

def jetsam_summary(path):
    try:
        text = open(path).read()
        header, _, body = text.partition("\n")
        data = json.loads(body)
        procs = data.get("processes", [])
        killed = sorted({p.get("name", "?") + (" (" + p["reason"] + ")" if p.get("reason") else "")
                         for p in procs if p.get("reason") and "idle-exit" not in p["reason"]})
        if len(killed) > 6: killed = killed[:6] + [f"+{len(killed) - 6} more"]
        largest = data.get("largestProcess") or (max(procs, key=lambda p: p.get("rpages", 0)).get("name") if procs else "?")
        when = json.loads(header).get("timestamp", "")[:19]
        return f"{os.path.basename(path)}: {when} killed (not idle) [{', '.join(killed) or 'none named'}], largest {largest}"
    except Exception as e:
        return f"{os.path.basename(path)}: unreadable ({e})"

jetsams = [p for p in new["system"] if os.path.basename(p).startswith("JetsamEvent-")]
print(f"Pulled {len(new['system'])} system log(s), {len(new['app'])} app file(s) into {OUT}.")
for p in jetsams: print("  " + jetsam_summary(p))
for p in new["app"]:
    if os.path.basename(p).startswith("crash-"): print("  app crash report: " + os.path.basename(p))
PY
