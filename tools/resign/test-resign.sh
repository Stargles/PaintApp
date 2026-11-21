#!/bin/bash
# Behavioural tests for tools/resign/resign.sh. No build, no device, no portal, no keychain:
# xcodebuild, xcrun (devicectl), security, codesign, osascript and pmset are fakes that record
# their calls; git is real, over a local fixture origin.
#   bash tools/resign/test-resign.sh [script]
set -euo pipefail
SCRIPT=${1:-$(cd "$(dirname "$0")" && pwd)/resign.sh}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/resign-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FAKE="$WORK/fake"; BIN="$WORK/bin"; CFG="$WORK/config"; STAGE="$WORK/stage"
mkdir -p "$FAKE" "$BIN" "$CFG" "$STAGE"
UUID=E3B83820-DF74-5042-B52B-0D5BA17E4877
PASS=0

# ---- fakes
cat > "$BIN/xcodebuild" <<'EOF'
#!/bin/bash
echo "xcodebuild $*" >> "$FAKE_DIR/calls"
[[ "$1" == clean ]] && exit 0
dd=""; prev=""; for a in "$@"; do [[ "$prev" == -derivedDataPath ]] && dd=$a; prev=$a; done
cat "$FAKE_DIR/build_out" 2>/dev/null || true
rc=$(cat "$FAKE_DIR/build_rc" 2>/dev/null || echo 0)
[[ -e "$FAKE_DIR/device_ok" && "$*" == *platform=iOS,id=* ]] && rc=0
[[ "$rc" == 0 ]] || exit "$rc"
app="$dd/Build/Products/Release-iphoneos/PaintSoftware.app"
mkdir -p "$app"
printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CreationDate</key><date>%s</date><key>ExpirationDate</key><date>%s</date></dict></plist>' \
  "$(cat "$FAKE_DIR/profile_created")" "$(cat "$FAKE_DIR/profile_exp")" > "$app/embedded.mobileprovision"
git -C "$(dirname "$dd")/.." rev-parse HEAD > "$app/source"
EOF
cat > "$BIN/xcrun" <<'EOF'
#!/bin/bash
echo "xcrun $*" >> "$FAKE_DIR/calls"
case "$2 $3" in
  "list devices") cat "$FAKE_DIR/devices" ;;
  "device install") exit "$(cat "$FAKE_DIR/install_rc" 2>/dev/null || echo 0)" ;;
  "device info") echo "PaintSoftware   Starg.PaintSoftware   1.0" ;;
esac
EOF
cat > "$BIN/security" <<'EOF'
#!/bin/bash
echo "security $1" >> "$FAKE_DIR/calls"
case "$1" in
  find-identity) echo '1) ABC "Apple Development: Fixture"' ;;
  cms) cat "${@: -1}" ;;
esac
EOF
printf '#!/bin/bash\necho "codesign $*" >> "$FAKE_DIR/calls"\n' > "$BIN/codesign"
printf '#!/bin/bash\necho "osascript $*" >> "$FAKE_DIR/notify"\n' > "$BIN/osascript"
printf '#!/bin/bash\necho "pmset $*" >> "$FAKE_DIR/calls"\n' > "$BIN/pmset"
printf '#!/bin/bash\nexit 0\n' > "$BIN/caffeinate"
chmod +x "$BIN"/*

# ---- fixture repository: origin with installed -> next on main, and an unrelated branch
G() { GIT_AUTHOR_NAME=F GIT_AUTHOR_EMAIL=f@x.invalid GIT_COMMITTER_NAME=F GIT_COMMITTER_EMAIL=f@x.invalid git "$@"; }
SRC="$WORK/src"; ORIGIN="$WORK/origin.git"; CLONE="$WORK/PaintApp"
G init -q -b main "$SRC"
commit() { echo "$1" > "$SRC/$1"; G -C "$SRC" add "$1"; G -C "$SRC" commit -q -m "$1"; G -C "$SRC" rev-parse HEAD; }
OLD=$(commit old)
INSTALLED=$(commit installed)
G clone -q --bare "$SRC" "$ORIGIN"
G clone -q "$ORIGIN" "$CLONE"
NEXT=$(commit next)
G -C "$SRC" checkout -q -b other "$OLD"; UNRELATED=$(commit unrelated); G -C "$SRC" checkout -q main
G -C "$SRC" push -q "$ORIGIN" main

cat > "$CFG/.env" <<EOF
KEYCHAIN_PASSWORD=fixture
SIGNING_IDENTITY="Apple Development: Fixture"
PROJECT_DIR=$CLONE
PROJECT_FILE=PaintSoftware.xcodeproj
SCHEME=PaintSoftware
EOF

iso() { date -u -r "$(( $(date +%s) + $1 ))" '+%Y-%m-%dT%H:%M:%SZ'; }
old_build() { mkdir -p "$STAGE/device-old/PaintSoftware.app"; echo "$STAGE/device-old/PaintSoftware.app"; }

# reset <installed expiry offset> — fresh state, runtime, fakes; iPad reachable, portal mints +7 d.
reset() {
    rm -rf "$FAKE"/* "$CFG/resign_runtime" "$CFG/resign.log" "$STAGE"/*
    printf 'LAST_APP_PATH=%s\nLAST_SOURCE_SHA=%s\nLAST_PROFILE_EXPIRATION=%s\nLAST_PROFILE_CREATION=%s\n' \
        "$(old_build)" "$INSTALLED" "$(iso "$1")" "$(iso $(( $1 - 604800 )))" > "$CFG/resign_state"
    printf 'X  x  %s  available (paired)  iPad\n' "$UUID" > "$FAKE/devices"
    iso 604800 > "$FAKE/profile_exp"; iso 0 > "$FAKE/profile_created"
    : > "$FAKE/calls"
    G -C "$CLONE" remote set-url origin "$ORIGIN"
    G -C "$CLONE" checkout -q --detach "$INSTALLED"
}
run() { local rc=0
    FAKE_DIR="$FAKE" RESIGN_PATH_PREFIX="$BIN" RESIGN_CONFIG_DIR="$CFG" RESIGN_STAGE_ROOT="$STAGE" \
        RESIGN_RUN_USER="$(id -un)" bash "$SCRIPT" "$@" || rc=$?; [[ $rc == 0 ]] || die "script exited $rc"
}
get() { sed -n "s/^$1=//p" "$CFG/resign_state"; }
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
die() { echo "FAIL $1"; echo "--- log"; cat "$CFG/resign.log" 2>/dev/null; echo "--- calls"; cat "$FAKE/calls"; exit 1; }
valid_state() {
    [[ "$(get LAST_SOURCE_SHA)" =~ ^[0-9a-f]{40}$ && -n "$(get LAST_PROFILE_EXPIRATION)" && -d "$(get LAST_APP_PATH)" ]] \
        || die "$1: state no longer names an existing installed build"
}

# 1. Nothing due, nothing staged: no device query, no build, nothing logged.
reset 259200; run
[[ ! -s "$FAKE/calls" && ! -s "$CFG/resign.log" ]] || die "idle tick touched a tool or the log"
ok "idle tick makes no devicectl/xcodebuild call"

# 2. Expired, iPad locked away: signs for the generic destination, stages, does not install or notify.
reset -300; printf 'X  x  %s  unavailable  iPad\n' "$UUID" > "$FAKE/devices"; run
grep -q 'xcodebuild build .*-destination generic/platform=iOS' "$FAKE/calls" || die "did not build generic"
! grep -q 'platform=iOS,id=' "$FAKE/calls" || die "named the iPad while signing"
! grep -q 'device install' "$FAKE/calls" || die "installed on an unavailable iPad"
[[ ! -e "$FAKE/notify" ]] || die "notified for an unreachable iPad"
STAGED=$(get STAGED_APP_PATH)
[[ -d "$STAGED" && "$(get STAGED_SOURCE_SHA)" == "$NEXT" && "$(get LAST_SOURCE_SHA)" == "$INSTALLED" ]] || die "staging"
[[ "$(cat "$STAGED/source")" == "$NEXT" ]] || die "staged build is not of origin/main"
valid_state "unreachable"
ok "unreachable iPad at sign time: signs generic, stages, no install, no notify"

# 3. Same tick again while still away: no rebuild, one device query.
: > "$FAKE/calls"; run
! grep -q xcodebuild "$FAKE/calls" || die "rebuilt a staged build"
[[ "$(grep -c 'list devices' "$FAKE/calls")" == 1 ]] || die "device query count"
ok "pending install while away: no rebuild, only a device query"

# 4. iPad appears: installs the staged build, promotes it, deletes the superseded one.
printf 'X  x  %s  available (paired)  iPad\n' "$UUID" > "$FAKE/devices"; : > "$FAKE/calls"; run
grep -q "device install app --device $UUID $STAGED" "$FAKE/calls" || die "no install"
[[ "$(get LAST_APP_PATH)" == "$STAGED" && "$(get LAST_SOURCE_SHA)" == "$NEXT" && -z "$(get STAGED_APP_PATH)" ]] || die "promotion"
[[ ! -e "$STAGE/device-old" ]] || die "superseded build kept"
valid_state "promote"
ok "iPad appears: installs, promotes staged to installed, deletes superseded build"

# 5. Fetch fails: rebuilds the installed source, no notification.
reset -300; G -C "$CLONE" remote set-url origin "$WORK/no-such-origin"; run
grep -q 'device install' "$FAKE/calls" || die "fetch-fail build not installed"
[[ "$(get LAST_SOURCE_SHA)" == "$INSTALLED" && "$(cat "$(get LAST_APP_PATH)/source")" == "$INSTALLED" ]] || die "fetch-fail source"
[[ ! -e "$FAKE/notify" ]] || die "notified for a fetch failure"
valid_state "fetch"
ok "fetch fails: builds and installs the installed source"

# 6. origin/main unrelated to the installed source: refuses to build and notifies.
reset -300; G -C "$SRC" push -q -f "$ORIGIN" "$UNRELATED:main"; run
! grep -q 'xcodebuild build' "$FAKE/calls" || die "built unrelated history"
[[ -e "$FAKE/notify" && -z "$(get STAGED_APP_PATH)" ]] || die "unrelated history not reported"
valid_state "unrelated"
G -C "$SRC" push -q -f "$ORIGIN" "$NEXT:main"
ok "unrelated origin/main: fails closed and notifies"

# 7. Inside the last hour the portal returns the same profile: quiet, then no rebuild until expiry.
reset 1800; get LAST_PROFILE_EXPIRATION > "$FAKE/profile_exp"; run
[[ -z "$(get STAGED_APP_PATH)" && ! -e "$FAKE/notify" ]] || die "same profile before expiry staged or notified"
grep -q 'VERDICT: WAIT — the portal returned the current profile' "$CFG/resign.log" || die "same-profile verdict"
: > "$FAKE/calls"; run
[[ ! -s "$FAKE/calls" ]] || die "rebuilt before expiry after a same-profile answer"
ok "same profile before expiry: quiet skip, no rebuild until expiry"

# 8. After expiry the portal still returns the dead profile: fail and notify.
reset -600; get LAST_PROFILE_EXPIRATION > "$FAKE/profile_exp"; run
[[ -e "$FAKE/notify" && -z "$(get STAGED_APP_PATH)" ]] || die "stale profile after expiry not reported"
grep -q 'VERDICT: FAIL — the build reused an expired profile' "$CFG/resign.log" || die "stale verdict"
valid_state "stale"
ok "same profile after expiry: FAIL and notify"

# 9. No Apple ID session: notifies; a second failure within the backoff does not rebuild.
reset -600; echo 'error: No Accounts' > "$FAKE/build_out"; echo 65 > "$FAKE/build_rc"; run
grep -q 'no Apple ID session' "$FAKE/notify" || die "No Accounts not notified"
: > "$FAKE/calls"; run
! grep -q xcodebuild "$FAKE/calls" || die "rebuilt inside the failure backoff"
ok "No Accounts: notifies once, backs off"

# 10. Portal has no device: falls back to naming the iPad.
reset -600; echo 'error: Your team has no devices from which to generate a provisioning profile' > "$FAKE/build_out"
echo 65 > "$FAKE/build_rc"
touch "$FAKE/device_ok"; run
grep -q "xcodebuild build .*platform=iOS,id=$UUID.*-allowProvisioningDeviceRegistration" "$FAKE/calls" || die "no device fallback"
[[ "$(get LAST_SOURCE_SHA)" == "$NEXT" ]] || die "device fallback did not produce an installed build"
ok "portal has no device: retries with the iPad named"

# 11. Install fails on a reachable iPad: staged kept, state still the old build, no notification.
reset -300; echo 1 > "$FAKE/install_rc"; run
[[ -n "$(get STAGED_APP_PATH)" && "$(get LAST_SOURCE_SHA)" == "$INSTALLED" && ! -e "$FAKE/notify" ]] || die "install failure handling"
valid_state "install-fail"
ok "install failure: keeps staged and installed records, retries quietly"

# 12. A staged build whose profile has died is dropped and signing runs again.
rm -f "$FAKE/install_rc"
sed -i '' "s/^STAGED_PROFILE_EXPIRATION=.*/STAGED_PROFILE_EXPIRATION=$(iso -60)/" "$CFG/resign_state"
DEAD=$(get STAGED_APP_PATH); rm -f "$CFG/resign_runtime"; : > "$FAKE/calls"; run
[[ ! -e "$DEAD" || "$(get LAST_APP_PATH)" == "$DEAD" ]] || die "dead staged build kept"
grep -q 'xcodebuild build' "$FAKE/calls" || die "did not re-sign after dropping a dead staged build"
valid_state "dead-staged"
ok "expired staged build: dropped, re-signed"

# 13. Lock contention: a second tick exits at once and touches nothing.
reset -300
lockf -k "$CFG/resign.lock" sleep 60 & HOLDER=$!
sleep 0.5; run
[[ ! -s "$FAKE/calls" && -z "$(get STAGED_APP_PATH)" ]] || die "ran while the lock was held"
pkill -9 -P "$HOLDER" 2>/dev/null || true; kill -9 "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true
run
[[ "$(get LAST_SOURCE_SHA)" == "$NEXT" ]] || die "a killed holder wedged the lock"
ok "lock contention: second tick exits; a dead holder does not wedge it"

# 14. Dry run plans wakes around expiry and touches nothing.
reset 7200; out=$(run --dry-run)
[[ ! -s "$FAKE/calls" ]] || die "dry run called a tool"
[[ "$(grep -c 'would wake at' <<< "$out")" == 3 ]] || die "dry run wake plan: $out"
ok "dry run: three wakes planned, no tool called"

echo "All $PASS passed."
