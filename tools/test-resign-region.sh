#!/bin/bash
set -euo pipefail
CANDIDATE=${1:?candidate script required}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/resign-test.XXXXXX")
cleanup(){ python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$WORK"; }
trap cleanup EXIT
SEED="$WORK/Seed.app"
mkdir -p "$SEED" "$WORK/bin"
cat > "$SEED/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.example.painttest</string><key>CFBundleName</key><string>PaintTest</string><key>CFBundleExecutable</key><string>PaintTest</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
printf '#!/bin/sh\nexit 0\n' > "$SEED/PaintTest"
chmod +x "$SEED/PaintTest"
printf 'locally-signed-profile-fixture-v1\n' > "$SEED/embedded.mobileprovision"
codesign --force --sign - --timestamp=none "$SEED" >/dev/null
codesign --verify --deep --strict "$SEED" >/dev/null

# The test runs the candidate's actual clean/build/verify/install source region.
awk '/^mint_outcome\(\)/{copy=1} copy{print} /^}/{if(copy) exit}' "$CANDIDATE" > "$WORK/mint_outcome.sh"
awk '/^CONFIGURATION="\$\{CONFIGURATION:-Release\}"/{copy=1} /^# --- Record success and schedule next wake ---/{copy=0} copy' "$CANDIDATE" > "$WORK/region.sh"
awk '/^# Select a build source that never moves backwards/{copy=1} /^# --- Make sure we are about to build a monotonic source ---/{copy=0} copy' "$CANDIDATE" > "$WORK/provenance.sh"
[[ -s "$WORK/mint_outcome.sh" && -s "$WORK/region.sh" && -s "$WORK/provenance.sh" ]] || { echo 'could not extract candidate helpers/regions'; exit 1; }

# Exercise the candidate's real Git ancestry and state helpers with a local fixture.
run_as_user(){ "$@"; }
. "$WORK/provenance.sh"
GIT_FIXTURE="$WORK/source-repo"
mkdir -p "$GIT_FIXTURE"
git -C "$GIT_FIXTURE" init -q -b main
git_fixture_commit(){
    local message=$1 path=$2
    printf '%s\n' "$message" > "$GIT_FIXTURE/$path"
    git -C "$GIT_FIXTURE" add "$path"
    GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
      GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
      git -C "$GIT_FIXTURE" commit -q -m "$message"
    git -C "$GIT_FIXTURE" rev-parse HEAD
}
OLD_SHA=$(git_fixture_commit old-source old.txt)
INSTALLED_SHA=$(git_fixture_commit installed-source installed.txt)
DESCENDANT_SHA=$(git_fixture_commit next-source next.txt)
git -C "$GIT_FIXTURE" checkout -q -b divergent "$OLD_SHA"
DIVERGED_SHA=$(git_fixture_commit divergent-source divergent.txt)
git -C "$GIT_FIXTURE" checkout -q main
[[ "$(select_build_source "$GIT_FIXTURE" "$INSTALLED_SHA" "$OLD_SHA")" == "$INSTALLED_SHA" ]] || { echo 'FAIL origin ancestor selected a downgrade'; exit 1; }
echo 'PASS origin-main-behind-keeps-installed-source'
[[ "$(select_build_source "$GIT_FIXTURE" "$INSTALLED_SHA" "$INSTALLED_SHA")" == "$INSTALLED_SHA" ]] || { echo 'FAIL equal source selection'; exit 1; }
echo 'PASS equal-source'
[[ "$(select_build_source "$GIT_FIXTURE" "$INSTALLED_SHA" "$DESCENDANT_SHA")" == "$DESCENDANT_SHA" ]] || { echo 'FAIL descendant source selection'; exit 1; }
echo 'PASS origin-main-descendant-advances-source'
for bad_last in '' invalid 0000000000000000000000000000000000000000; do
    if select_build_source "$GIT_FIXTURE" "$bad_last" "$OLD_SHA" >/dev/null 2>&1; then
        echo "FAIL invalid/missing last source accepted: $bad_last"; exit 1
    fi
done
if select_build_source "$GIT_FIXTURE" "$INSTALLED_SHA" "$DIVERGED_SHA" >/dev/null 2>&1; then
    echo 'FAIL unrelated source histories accepted'; exit 1
fi
echo 'PASS missing-invalid-unavailable-and-diverged-sources-fail-closed'
touch "$GIT_FIXTURE/untracked-deploy-fixture"
checkout_build_source "$GIT_FIXTURE" "$INSTALLED_SHA" || { echo 'FAIL selected source checkout'; exit 1; }
[[ "$(git -C "$GIT_FIXTURE" rev-parse HEAD)" == "$INSTALLED_SHA" && -f "$GIT_FIXTURE/untracked-deploy-fixture" ]] || { echo 'FAIL checkout did not preserve exact source/untracked fixture'; exit 1; }
echo 'PASS checkout-selected-immutable-source-preserves-untracked'
STATE_FIXTURE="$WORK/success-state"
write_success_state "$STATE_FIXTURE" '/fixture/Paint.app' "$INSTALLED_SHA" '2026-10-30T00:18:54Z' '2026-10-23T00:18:54Z'
grep -Fxq "LAST_SOURCE_SHA=$INSTALLED_SHA" "$STATE_FIXTURE" || { echo 'FAIL state omitted installed source SHA'; exit 1; }
cp "$STATE_FIXTURE" "$WORK/state-before-invalid-write"
if write_success_state "$STATE_FIXTURE" '/fixture/Paint.app' invalid expiry creation; then
    echo 'FAIL invalid source SHA was persisted'; exit 1
fi
cmp -s "$STATE_FIXTURE" "$WORK/state-before-invalid-write" || { echo 'FAIL invalid source write changed state'; exit 1; }
echo 'PASS source-state-persists-valid-sha-rejects-invalid'
INSTALL_LINE=$(grep -n 'xcrun devicectl device install app' "$CANDIDATE" | tail -1 | cut -d: -f1)
STATE_LINE=$(grep -n 'write_success_state "\$STATE_FILE"' "$CANDIDATE" | tail -1 | cut -d: -f1)
[[ -n "$INSTALL_LINE" && -n "$STATE_LINE" && "$STATE_LINE" -gt "$INSTALL_LINE" ]] || { echo 'FAIL source state write is not after install'; exit 1; }
echo 'PASS provenance-write-follows-successful-install'

run_case() {
    local name=$1 clean_rc=${2:-0} build_rc=${3:-0} mode=${4:-advanced} tamper=${5:-no}
    local d="$WORK/$name"
    mkdir -p "$d/logs" "$d/project"
    cat > "$d/case.sh" <<'CASE'
#!/bin/bash
set -euo pipefail
NAME=$1 CLEAN_RC=$2 BUILD_RC=$3 MINT_MODE=$4 TAMPER=$5
PROJECT_DIR="$WORK/$NAME/project" PROJECT_FILE=Paint.xcodeproj SCHEME=PaintTest CONFIGURATION=Release
DEVICE_UUID=fixture-device RUN_USER=$(id -un) BUILD_LOG_DIR="$PROJECT_DIR/../logs" NOW=$(date +%s)
STATE_FILE="$PROJECT_DIR/../state" SOURCE_SHA=0123456789abcdef0123456789abcdef01234567
[[ "$MINT_MODE" == aged ]] && NOW=$((NOW - 15))
PROFILE_DUE_WINDOW=3600 PROFILE_RENEW_DELAY=120
FIXTURE_FAIL_EPOCH=no
[[ "$MINT_MODE" == clockfail ]] && FIXTURE_FAIL_EPOCH=yes
date(){ if [[ "$FIXTURE_FAIL_EPOCH" == yes && $# == 1 && "$1" == +%s ]]; then return 1; fi; command date "$@"; }
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
BUILD_LOG="$BUILD_LOG_DIR/build.log"
mkdir -p "$BUILD_LOG_DIR"
export FIXTURE_MINT_MODE=$MINT_MODE FIXTURE_TAMPER=$TAMPER FIXTURE_CLEAN_RC=$CLEAN_RC FIXTURE_BUILD_RC=$BUILD_RC
log(){ :; }
log_block(){ :; }
schedule_next_wake(){ :; }
verdict(){ printf '%s\n' "$1" > "$PROJECT_DIR/../verdict"; }
fail_retry(){ verdict FAIL "$1"; exit 1; }
iso_to_epoch(){ date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s' 2>/dev/null; }
read_profile_dates(){
    PROFILE_CREATION_ISO=$(date -u -r "$NOW" '+%Y-%m-%dT%H:%M:%SZ')
    case "$FIXTURE_MINT_MODE" in
      clockfail|advanced) PROFILE_EXPIRATION_ISO=$(date -u -v+8d -r "$NOW" '+%Y-%m-%dT%H:%M:%SZ'); PROFILE_EXPIRATION_EPOCH=$((NOW - 86400)) ;;
      short) PROFILE_EXPIRATION_ISO=$(date -u -v+4d -r "$NOW" '+%Y-%m-%dT%H:%M:%SZ'); PROFILE_EXPIRATION_EPOCH=$((NOW - 86400)) ;;
      early) PROFILE_EXPIRATION_ISO=$(date -u -v+2d -r "$NOW" '+%Y-%m-%dT%H:%M:%SZ'); PROFILE_EXPIRATION_EPOCH=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$PROFILE_EXPIRATION_ISO" '+%s') ;;
      stale) PROFILE_EXPIRATION_ISO=$(date -u -v-1d -r "$NOW" '+%Y-%m-%dT%H:%M:%SZ'); PROFILE_EXPIRATION_EPOCH=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$PROFILE_EXPIRATION_ISO" '+%s') ;;
      aged) PROFILE_EXPIRATION_ISO=$(date -u -v+5d -r "$NOW" '+%Y-%m-%dT%H:%M:%SZ'); PROFILE_EXPIRATION_EPOCH=$((NOW - 86400)) ;;
    esac
}
run_as_user(){
    local cmd=$1; shift
    if [[ "$cmd" == /usr/bin/xcodebuild ]]; then
      local stage=$1; shift
      printf '%s' "$stage" >> "$BUILD_LOG_DIR/args.log"
      for arg in "$@"; do printf '|%s' "$arg" >> "$BUILD_LOG_DIR/args.log"; done
      printf '\n' >> "$BUILD_LOG_DIR/args.log"
      if [[ "$stage" == clean ]]; then return "$FIXTURE_CLEAN_RC"; fi
      if [[ "$stage" == build ]]; then
        [[ "$FIXTURE_BUILD_RC" == 0 ]] || { echo 'error: fixture build failure'; return "$FIXTURE_BUILD_RC"; }
        local app="$DERIVED_DATA/Build/Products/Release-iphoneos/PaintTest.app"
        mkdir -p "$(dirname "$app")"
        ditto "$SEED_APP" "$app"
        if [[ "$FIXTURE_TAMPER" == yes ]]; then printf 'replaced-profile\n' > "$app/embedded.mobileprovision"; fi
        return 0
      fi
      return 2
    fi
    if [[ "$cmd" == /usr/bin/xcrun ]]; then
      printf 'INSTALL\n' >> "$BUILD_LOG_DIR/actions.log"
      return 0
    fi
    "$cmd" "$@"
}
. "$MINT_HELPER"
. "$PROVENANCE"
SEED_APP=$SEED_APP
. "$REGION"
if [[ -f "$BUILD_LOG_DIR/actions.log" ]] && grep -q '^INSTALL$' "$BUILD_LOG_DIR/actions.log"; then
  write_success_state "$STATE_FILE" "$APP_PATH" "$SOURCE_SHA" "$PROFILE_EXPIRATION_ISO" "$PROFILE_CREATION_ISO"
fi
CASE
    chmod +x "$d/case.sh"
    set +e
    WORK="$WORK" SEED_APP="$SEED" REGION="$WORK/region.sh" MINT_HELPER="$WORK/mint_outcome.sh" PROVENANCE="$WORK/provenance.sh" bash "$d/case.sh" "$name" "$clean_rc" "$build_rc" "$mode" "$tamper"
    local rc=$?
    set -e
    printf '%s %s %s\n' "$name" "$rc" "$(cat "$d/verdict" 2>/dev/null || echo no-verdict)"
}
expect(){
    local name=$1 wanted=$2 rc=$3 got
    got=$(run_case "$name" "${4:-0}" "${5:-0}" "${6:-advanced}" "${7:-no}")
    [[ "$got" == "$name $rc $wanted" ]] || { echo "FAIL $name expected rc=$rc verdict=$wanted; got $got"; exit 1; }
    echo "PASS $name"
}
expect clean-failure FAIL 1 9 0 advanced no
[[ ! -f "$WORK/clean-failure/logs/args.log" ]] || ! grep -q '^build|' "$WORK/clean-failure/logs/args.log"
expect build-failure FAIL 1 0 9 advanced no
expect changed-profile FAIL 1 0 0 advanced yes
expect short-profile FAIL 1 0 0 short no
expect aged-start FAIL 1 0 0 aged no
expect clock-failure FAIL 1 0 0 clockfail no
valid_result=$(run_case valid-new-profile 0 0 advanced no)
[[ "$valid_result" == 'valid-new-profile 0 no-verdict' ]] || { echo "valid install failed: $valid_result"; exit 1; }
echo 'PASS valid-new-profile'
[[ -f "$WORK/valid-new-profile/logs/actions.log" ]] || { echo 'valid profile was not installed'; exit 1; }
grep -Fxq 'LAST_SOURCE_SHA=0123456789abcdef0123456789abcdef01234567' "$WORK/valid-new-profile/state" || { echo 'successful fixture install did not persist source SHA'; exit 1; }
expect too-early SKIP 0 0 0 early no
[[ ! -f "$WORK/too-early/logs/actions.log" ]] || { echo 'too-early profile installed'; exit 1; }
expect stale-profile FAIL 1 0 0 stale no
for rejected in clean-failure build-failure changed-profile short-profile aged-start clock-failure too-early stale-profile; do
  [[ ! -f "$WORK/$rejected/logs/actions.log" ]] || { echo "$rejected unexpectedly called device install"; exit 1; }
  [[ ! -f "$WORK/$rejected/state" ]] || { echo "$rejected unexpectedly persisted successful-install state"; exit 1; }
done
for case_name in valid-new-profile short-profile changed-profile build-failure; do
  args="$WORK/$case_name/logs/args.log"
  if [[ -f "$args" ]]; then
    grep -Fq -- "-derivedDataPath|$WORK/$case_name/project/build/DerivedData" "$args" || { echo "missing shared DerivedData in $case_name"; exit 1; }
    grep -Fq -- '|-configuration|Release' "$args" || { echo "missing Release config in $case_name"; exit 1; }
  fi
done
# Both clean and build must receive identical common args.
args="$WORK/valid-new-profile/logs/args.log"
clean_line=$(sed -n '1p' "$args" | cut -d'|' -f2- | sed 's/|-quiet$//')
build_line=$(sed -n '2p' "$args" | cut -d'|' -f2- | sed 's/|-allowProvisioningUpdates.*//')
[[ "$clean_line" == "$build_line" ]] || { echo 'clean/build argument sets differ'; exit 1; }
echo 'PASS shared clean/build arguments'
echo 'All renewal-region tests passed.'
