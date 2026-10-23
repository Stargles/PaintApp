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
[[ -s "$WORK/mint_outcome.sh" && -s "$WORK/region.sh" ]] || { echo 'could not extract candidate helpers/region'; exit 1; }

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
SEED_APP=$SEED_APP
. "$REGION"
CASE
    chmod +x "$d/case.sh"
    set +e
    WORK="$WORK" SEED_APP="$SEED" REGION="$WORK/region.sh" MINT_HELPER="$WORK/mint_outcome.sh" bash "$d/case.sh" "$name" "$clean_rc" "$build_rc" "$mode" "$tamper"
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
expect too-early SKIP 0 0 0 early no
[[ ! -f "$WORK/too-early/logs/actions.log" ]] || { echo 'too-early profile installed'; exit 1; }
expect stale-profile FAIL 1 0 0 stale no
for rejected in clean-failure build-failure changed-profile short-profile aged-start clock-failure too-early stale-profile; do
  [[ ! -f "$WORK/$rejected/logs/actions.log" ]] || { echo "$rejected unexpectedly called device install"; exit 1; }
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
