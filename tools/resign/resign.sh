#!/bin/bash
# Keeps the sideloaded app's free-account provisioning profile (~7 days) alive. docs/RESIGN.md.
#
# Two stages over one state file, so neither waits on what only the other needs:
#   sign    - Mac + Apple ID only. When the newest profile is expired or within an hour of it, build
#             Release for the generic iOS destination, verify it, copy it to $STAGE_ROOT and record it
#             as STAGED_*. The iPad is never named.
#   install - iPad only. When a build is staged and the iPad is listed available, install it, then
#             promote STAGED_* to LAST_* and delete the superseded build.
#
# Run every 5 min by the user LaunchAgent and hourly by the root LaunchDaemon; only the root run can
# arm pmset wakes around expiry. A run with nothing to do reads two small files and exits.
#
#   resign.sh            one tick
#   resign.sh --dry-run  print what a tick would do; no build, install, device query or wake
set -euo pipefail

CONFIG_DIR=${RESIGN_CONFIG_DIR:-/Users/juliapark/.config/paintapp}
ENV_FILE=${RESIGN_ENV_FILE:-$CONFIG_DIR/.env}
STATE_FILE=${RESIGN_STATE_FILE:-$CONFIG_DIR/resign_state}
RUNTIME_FILE=${RESIGN_RUNTIME_FILE:-$CONFIG_DIR/resign_runtime}
LOG_FILE=${RESIGN_LOG_FILE:-$CONFIG_DIR/resign.log}
BUILD_LOG_DIR=${RESIGN_BUILD_LOG_DIR:-$CONFIG_DIR/build-logs}
LOCK_FILE=${RESIGN_LOCK_FILE:-$CONFIG_DIR/resign.lock}
STAGE_ROOT=${RESIGN_STAGE_ROOT:-/Users/juliapark/PaintWork}
RUN_USER=${RESIGN_RUN_USER:-juliapark}
DEVICE_UUID=${RESIGN_DEVICE_UUID:-E3B83820-DF74-5042-B52B-0D5BA17E4877}
BUNDLE_ID=Starg.PaintSoftware
AWAY_SETTLE=${AWAY_SETTLE:-120}   # seconds the app must have been in the background before an install may close it
APP_EXECUTABLE=PaintSoftware
WAKE_OWNER=com.paintapp.resign

DUE_WINDOW=3600          # sign when the newest profile is expired or this close to it
RENEW_DELAY=120          # the portal mints a new profile only after the old one expires
FAIL_BACKOFF=900         # after a failed sign, wait this long before building again
MIN_INSTALL_LIFE=3600    # never install a profile with less life than this
NOTIFY_INTERVAL=10800    # at most one notification per this many seconds
INSTALL_FAIL_NOTIFY=12   # consecutive install failures on a reachable iPad before notifying
LOG_MAX_BYTES=2000000

PATH="${RESIGN_PATH_PREFIX:+$RESIGN_PATH_PREFIX:}/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"
export PATH

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
IS_ROOT=0
[[ "$(id -u)" == "0" ]] && IS_ROOT=1
NOW=${RESIGN_FAKE_NOW:-$(date +%s)}
SELF="${BASH_SOURCE[0]}"

# ---------------------------------------------------------------- logging, user context, notify

log() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') [$([[ $IS_ROOT == 1 ]] && echo daemon || echo agent)] $1"
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
    [[ $DRY_RUN == 1 || -t 1 ]] && printf '%s\n' "$line"
    return 0
}

log_block() { printf '%s\n' "${1:-(no output)}" | sed 's/^/    /' >> "$LOG_FILE" 2>/dev/null || true; }

rotate_log() {
    local size
    size=$(stat -f %z "$LOG_FILE" 2>/dev/null) || return 0
    if (( size > LOG_MAX_BYTES )); then
        tail -n 5000 "$LOG_FILE" > "$LOG_FILE.tmp" && cat "$LOG_FILE.tmp" > "$LOG_FILE"
        rm -f "$LOG_FILE.tmp"
    fi
}

# Root runs the user's tools in the user's GUI session, where the keychain and Xcode's Apple ID live.
run_as_user() {
    if [[ $IS_ROOT == 1 ]]; then
        launchctl asuser "$(id -u "$RUN_USER")" sudo -n -u "$RUN_USER" -H env PATH="$PATH" "$@"
    else
        "$@"
    fi
}

# Git as the repo's owner: root would trip git's safe.directory check. Hooks never run here.
ugit() { run_as_user git -c core.hooksPath=/dev/null "$@"; }

own() { [[ $IS_ROOT == 1 ]] && chown "$RUN_USER" "$@" 2>/dev/null; return 0; }

# run_bounded <seconds> <outfile> <cmd...> — a hung tool cannot hold the lock forever.
run_bounded() {
    local secs=$1 out=$2 pid watchdog rc=0
    shift 2
    "$@" > "$out" 2>&1 &
    pid=$!
    ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 5; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    watchdog=$!
    wait "$pid" || rc=$?
    kill -TERM "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    return $rc
}

# notify <message> — only for what the owner must fix by hand; rate-limited.
notify() {
    local msg=${1:0:200}
    if (( NOW - ${LAST_NOTIFY:-0} < NOTIFY_INTERVAL )); then
        log "(notification suppressed: one was sent $(( (NOW - LAST_NOTIFY) / 60 )) min ago)"
        return 0
    fi
    msg=${msg//\"/}
    msg=${msg//\\/}
    run_as_user osascript -e "display notification \"$msg\" with title \"PaintApp auto-resign needs you\"" >/dev/null 2>&1 || true
    LAST_NOTIFY=$NOW
    save_runtime
}

# ---------------------------------------------------------------- state

STATE_KEYS=(LAST_APP_PATH LAST_SOURCE_SHA LAST_PROFILE_EXPIRATION LAST_PROFILE_CREATION
            STAGED_APP_PATH STAGED_SOURCE_SHA STAGED_PROFILE_EXPIRATION STAGED_PROFILE_CREATION)
RUNTIME_KEYS=(NEXT_SIGN_AFTER LAST_NOTIFY INSTALL_FAILS QUIET_NOTE QUIET_NOTE_AT)

load_keys() {   # load_keys <file> <key...>
    local file=$1 key
    shift
    for key in "$@"; do
        printf -v "$key" '%s' "$(sed -n "s/^$key=//p" "$file" 2>/dev/null | tail -1)"
    done
}

write_keys() {   # write_keys <file> <key...> — sibling temp file, then rename: never half-written
    local file=$1 tmp key
    shift
    tmp=$(mktemp "$file.tmp.XXXXXX") || return 2
    for key in "$@"; do
        if [[ -n "${!key}" ]]; then printf '%s=%s\n' "$key" "${!key}"; fi
    done > "$tmp" || { rm -f "$tmp"; return 2; }
    chmod 600 "$tmp"
    own "$tmp"
    mv -f "$tmp" "$file" || { rm -f "$tmp"; return 2; }
}

save_state() {
    [[ "$LAST_SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || return 2
    [[ -z "$STAGED_APP_PATH" || "$STAGED_SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || return 2
    write_keys "$STATE_FILE" "${STATE_KEYS[@]}"
}

save_runtime() { write_keys "$RUNTIME_FILE" "${RUNTIME_KEYS[@]}" || log "WARNING: could not write $RUNTIME_FILE"; }

clear_staged() { STAGED_APP_PATH=""; STAGED_SOURCE_SHA=""; STAGED_PROFILE_EXPIRATION=""; STAGED_PROFILE_CREATION=""; }

iso_to_epoch() { date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s" 2>/dev/null; }

# The newest profile we hold: the staged one if any, else the installed one. Empty if neither parses.
newest_expiry() {
    local iso=${STAGED_PROFILE_EXPIRATION:-$LAST_PROFILE_EXPIRATION}
    [[ -n "$iso" ]] && iso_to_epoch "$iso" || true
}

# Delete a build folder this job made, never anything else and never what the state still names.
remove_build() {
    local app=$1 dir
    dir=$(dirname "$app")
    [[ "$dir" == "$STAGE_ROOT"/device-* && -d "$dir" ]] || return 0
    [[ "$app" == "$LAST_APP_PATH" || "$app" == "$STAGED_APP_PATH" ]] && return 0
    rm -rf "$dir" && log "Deleted superseded build $dir"
}

# A quiet outcome (iPad away, profile not yet renewable) is logged once an hour, not every tick.
quiet() {
    if [[ "$1" != "$QUIET_NOTE" ]] || (( NOW - ${QUIET_NOTE_AT:-0} >= 3600 )); then
        log "VERDICT: WAIT — $1"
        QUIET_NOTE=$1
        QUIET_NOTE_AT=$NOW
        save_runtime
    fi
}

# ---------------------------------------------------------------- wakes (root only)

ensure_wake() {   # ensure_wake <epoch>
    local when sched
    when=$(date -r "$1" "+%m/%d/%Y %H:%M:%S") || return 1
    sched=$(pmset -g sched 2>&1) || return 1
    [[ "$sched" == *"wakeorpoweron at $when by '$WAKE_OWNER'"* ]] && return 0
    pmset schedule wakeorpoweron "$when" "$WAKE_OWNER" >/dev/null 2>&1 || { log "WARNING: could not schedule wake at $when"; return 1; }
    log "Wake scheduled: $when"
}

# Wake an hour before expiry, just after it (when the portal will mint), and an hour after that.
# With nothing ahead of us (expired, still failing), wake hourly to retry.
plan_wakes() {
    local expiry=$1 c
    WAKES=()
    if [[ -n "$expiry" ]]; then
        for c in $((expiry - DUE_WINDOW)) $((expiry + RENEW_DELAY)) $((expiry + RENEW_DELAY + 3600)); do
            (( c > NOW )) && WAKES+=("$c")
        done
    fi
    (( ${#WAKES[@]} )) || WAKES=($((NOW + 3600)))
}

schedule_wakes() {
    local c
    plan_wakes "$(newest_expiry)"
    for c in "${WAKES[@]}"; do
        if [[ $DRY_RUN == 1 ]]; then log "would wake at $(date -r "$c" '+%m/%d/%Y %H:%M:%S')"
        elif [[ $IS_ROOT == 1 ]]; then ensure_wake "$c" || true
        fi
    done
}

# ---------------------------------------------------------------- sign

# Advance only to a descendant of the installed source; keep the installed source while main is
# behind it; refuse unrelated or missing history.
select_build_source() {   # select_build_source <repo> <installed sha> <candidate sha>
    local repo=$1 installed=$2 candidate=$3
    [[ "$installed" =~ ^[0-9a-f]{40}$ && "$candidate" =~ ^[0-9a-f]{40}$ ]] || return 2
    [[ "$(ugit -C "$repo" rev-parse --verify -q "$installed^{commit}")" == "$installed" ]] || return 2
    [[ "$(ugit -C "$repo" rev-parse --verify -q "$candidate^{commit}")" == "$candidate" ]] || return 2
    if ugit -C "$repo" merge-base --is-ancestor "$installed" "$candidate"; then echo "$candidate"; return 0; fi
    if ugit -C "$repo" merge-base --is-ancestor "$candidate" "$installed"; then echo "$installed"; return 0; fi
    return 2
}

# sign_failed <message> <actionable: 1 notifies always, 0 only once the installed profile is dead>
sign_failed() {
    local installed_exp
    log "VERDICT: FAIL — $1"
    NEXT_SIGN_AFTER=$((NOW + FAIL_BACKOFF))
    save_runtime
    installed_exp=$(iso_to_epoch "$LAST_PROFILE_EXPIRATION" || echo 0)
    if [[ $2 == 1 ]] || (( installed_exp <= NOW )); then notify "$1"; fi
    return 1
}

unlock_keychain() {
    local keychain="/Users/$RUN_USER/Library/Keychains/login.keychain-db" probe out rc=0
    run_as_user security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$keychain" >/dev/null 2>&1 \
        || { sign_failed "could not unlock the login keychain — check KEYCHAIN_PASSWORD in $ENV_FILE" 1; return 1; }
    run_as_user security set-keychain-settings -t 3600 "$keychain" >/dev/null 2>&1 || true
    run_as_user security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$keychain" >/dev/null 2>&1 || true
    [[ "$(run_as_user security find-identity -v -p codesigning 2>&1)" == *"$SIGNING_IDENTITY"* ]] \
        || { sign_failed "signing identity '$SIGNING_IDENTITY' is not in the keychain" 1; return 1; }
    # A real signature proves the private key is usable without a GUI prompt.
    probe=$(run_as_user mktemp -d -t paintapp-resign) || { sign_failed "could not make a temp dir" 0; return 1; }
    run_as_user cp /bin/echo "$probe/probe"
    run_bounded 120 "$probe/out" run_as_user codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$probe/probe" || rc=$?
    out=$(cat "$probe/out" 2>/dev/null || true)
    run_as_user rm -rf "$probe" 2>/dev/null || true
    if (( rc != 0 )); then
        log_block "$out"
        sign_failed "codesign cannot use the private key non-interactively (exit $rc) — run a build by hand once and click Always Allow" 1
        return 1
    fi
}

# xcodebuild_run <log> <destination> [extra args] — clean and build with identical arguments, or a
# fresh profile is copied in without a new CodeSign task and the seal breaks.
xcodebuild_run() {
    local blog=$1 dest=$2
    shift 2
    local args=(-project "$PROJECT_DIR/$PROJECT_FILE" -scheme "$SCHEME" -configuration Release
                -destination "$dest" -derivedDataPath "$DERIVED_DATA")
    run_bounded 600 "$blog.clean" run_as_user xcodebuild clean "${args[@]}" || { cat "$blog.clean" >> "$blog"; return 1; }
    cat "$blog.clean" >> "$blog"
    rm -f "$blog.clean"
    local rc=0
    run_bounded 3600 "$blog.build" run_as_user xcodebuild build "${args[@]}" -allowProvisioningUpdates "$@" || rc=$?
    cat "$blog.build" >> "$blog"
    rm -f "$blog.build"
    return $rc
}

sign() {
    local blog fetched=0 candidate build_sha app profile_plist exp_iso cre_iso new_exp recorded_exp dest out_dir
    [[ -f "$ENV_FILE" ]] || { sign_failed "config $ENV_FILE is missing" 1; return 1; }
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    for key in KEYCHAIN_PASSWORD SIGNING_IDENTITY PROJECT_DIR PROJECT_FILE SCHEME; do
        [[ -n "${!key:-}" ]] || { sign_failed "$key is not set in $ENV_FILE" 1; return 1; }
    done
    DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
    mkdir -p "$BUILD_LOG_DIR" && own "$BUILD_LOG_DIR"
    ls -1t "$BUILD_LOG_DIR"/build-*.log 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null || true
    blog="$BUILD_LOG_DIR/build-$(date '+%Y%m%d-%H%M%S').log"
    : > "$blog" && own "$blog"
    log "=== Sign: newest profile ${STAGED_PROFILE_EXPIRATION:-$LAST_PROFILE_EXPIRATION} is due ==="
    caffeinate -i -w $$ >/dev/null 2>&1 &

    unlock_keychain || return 1

    # Source. Fetch is best-effort: without it, rebuild the installed source, which is always local.
    if run_bounded 120 "$blog.fetch" ugit -C "$PROJECT_DIR" fetch --prune origin \
        && candidate=$(ugit -C "$PROJECT_DIR" rev-parse --verify -q 'origin/main^{commit}'); then
        fetched=1
    else
        log "git fetch failed; rebuilding the installed source"
        candidate=$LAST_SOURCE_SHA
    fi
    rm -f "$blog.fetch"
    build_sha=$(select_build_source "$PROJECT_DIR" "$LAST_SOURCE_SHA" "$candidate") \
        || { sign_failed "installed source '${LAST_SOURCE_SHA:-none}' is missing from $PROJECT_DIR or unrelated to origin/main — refusing to build" 1; return 1; }
    [[ -z "$(ugit -C "$PROJECT_DIR" status --porcelain --untracked-files=no)" ]] \
        || { sign_failed "$PROJECT_DIR has uncommitted tracked changes — refusing to check out over them" 1; return 1; }
    ugit -C "$PROJECT_DIR" checkout -q --detach "$build_sha" \
        && [[ "$(ugit -C "$PROJECT_DIR" rev-parse HEAD)" == "$build_sha" ]] \
        || { sign_failed "could not check out $build_sha in $PROJECT_DIR" 1; return 1; }
    log "Building ${build_sha:0:8} (fetch $([[ $fetched == 1 ]] && echo ok || echo failed)) for generic/platform=iOS; log $blog"

    if ! xcodebuild_run "$blog" "generic/platform=iOS"; then
        if grep -q 'no devices from which to generate a provisioning profile' "$blog"; then
            log "Portal has no device for the profile; retrying with the iPad named"
            xcodebuild_run "$blog" "platform=iOS,id=$DEVICE_UUID" -allowProvisioningDeviceRegistration \
                || { sign_failed "the portal has no registered device and the iPad could not be named (unlock it once); log $blog" 0; return 1; }
        elif grep -q 'No Accounts' "$blog"; then
            sign_failed "Xcode has no Apple ID session — sign in at Xcode > Settings > Accounts" 1; return 1
        else
            log_block "$(grep -m 20 -E '(error|fatal error):|Code Sign' "$blog" || true)"
            sign_failed "xcodebuild failed; log $blog" 0; return 1
        fi
    fi

    app="$DERIVED_DATA/Build/Products/Release-iphoneos/$SCHEME.app"
    [[ -d "$app" ]] || { sign_failed "build succeeded but $app is missing" 1; return 1; }
    profile_plist=$(security cms -D -i "$app/embedded.mobileprovision" 2>/dev/null) || profile_plist=""
    exp_iso=$(plutil -extract ExpirationDate raw - -o - <<< "$profile_plist" 2>/dev/null) || exp_iso=""
    cre_iso=$(plutil -extract CreationDate raw - -o - <<< "$profile_plist" 2>/dev/null) || cre_iso=""
    new_exp=$(iso_to_epoch "$exp_iso") || { sign_failed "built app has no readable profile expiry" 1; return 1; }
    log "Built profile: created $cre_iso, expires $exp_iso"

    recorded_exp=$(newest_expiry)
    if [[ -n "$recorded_exp" ]] && (( new_exp <= recorded_exp )); then
        if (( recorded_exp > NOW - RENEW_DELAY )); then
            NEXT_SIGN_AFTER=$((recorded_exp + RENEW_DELAY))
            save_runtime
            quiet "the portal returned the current profile (expires $exp_iso); it mints a new one only after expiry — next try $(date -r "$NEXT_SIGN_AFTER" '+%m/%d %H:%M')"
            return 0
        fi
        sign_failed "the build reused an expired profile ($exp_iso) — check Xcode > Settings > Accounts" 1
        return 1
    fi
    (( new_exp - $(date +%s) >= MIN_INSTALL_LIFE )) || { sign_failed "new profile expires $exp_iso, under an hour away" 1; return 1; }
    run_as_user codesign --verify --deep --strict "$app" >> "$blog" 2>&1 \
        || { sign_failed "built app fails codesign --verify; log $blog" 1; return 1; }

    # Durable copy: DerivedData is rebuilt by the next sign; the staged build must outlive it.
    out_dir="$STAGE_ROOT/device-${build_sha:0:8}-Release-$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$cre_iso" '+%Y%m%d%H%M' 2>/dev/null || echo "$NOW")"
    dest="$out_dir/$SCHEME.app"
    run_as_user rm -rf "$out_dir"
    run_as_user mkdir -p "$out_dir"
    run_as_user ditto "$app" "$dest" && run_as_user codesign --verify --deep --strict "$dest" >> "$blog" 2>&1 \
        || { run_as_user rm -rf "$out_dir"; sign_failed "could not copy the build to $out_dir" 1; return 1; }

    local previous=$STAGED_APP_PATH
    STAGED_APP_PATH=$dest
    STAGED_SOURCE_SHA=$build_sha
    STAGED_PROFILE_EXPIRATION=$exp_iso
    STAGED_PROFILE_CREATION=$cre_iso
    save_state || { run_as_user rm -rf "$out_dir"; sign_failed "could not write $STATE_FILE" 1; return 1; }
    [[ -n "$previous" && "$previous" != "$dest" ]] && remove_build "$previous"
    NEXT_SIGN_AFTER=""
    save_runtime
    log "VERDICT: STAGED — ${build_sha:0:8}, profile expires $exp_iso, at $dest"
}

# ---------------------------------------------------------------- install

install_staged() {
    local list row out rc=0 previous
    list=$(run_as_user xcrun devicectl list devices 2>/dev/null) || list=""
    row=$(grep -F "$DEVICE_UUID" <<< "$list" || true)
    if [[ -z "$row" || "$row" == *unavailable* || "$row" != *available* ]]; then
        quiet "staged build waiting for the iPad (asleep, locked or off the network); installs when it appears"
        return 0
    fi
    out=$(mktemp -t paintapp-install)
    # An install terminates the running app and loses unsaved strokes. devicectl lists every live
    # process and says nothing of foreground or suspended, so a listed app is judged by the marker the
    # app keeps (`UncleanExitWatch`: `away` once the scene is in the background, `foreground` while
    # active; the app saves on leaving active, `ScenePhaseSaveGate`). Listed and `away` for
    # AWAY_SETTLE seconds (the save has long finished) installs; listed and anything else (foreground,
    # a fresh `away`, no marker, a failed read) defers. A failed or implausible process query defers too.
    run_bounded 60 "$out" run_as_user xcrun devicectl device info processes --device "$DEVICE_UUID" || rc=$?
    if (( rc != 0 )) || ! grep -q '/sbin/launchd' "$out"; then
        rm -f "$out"
        quiet "staged build waiting; could not list the iPad's running apps, so not installing"
        return 0
    fi
    if grep -Eq "/${APP_EXECUTABLE}\.app/${APP_EXECUTABLE}[[:space:]]*\$" "$out"; then
        local mark_dir mark_json="" mark_state mark_at mark_epoch
        mark_dir=$(mktemp -d -t paintapp-mark)
        if run_bounded 60 "$out" run_as_user xcrun devicectl device copy from --device "$DEVICE_UUID" \
            --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
            --source "Library/Application Support/CrashWatch/foreground.marker" --destination "$mark_dir/marker"; then
            mark_json=$(cat "$mark_dir/marker" 2>/dev/null || true)
        fi
        rm -rf "$mark_dir"
        mark_state=$(sed -n 's/.*"mark" *: *"\([a-z]*\)".*/\1/p' <<< "$mark_json")
        mark_at=$(sed -n 's/.*"at" *: *"\([0-9TZ:-]*\)".*/\1/p' <<< "$mark_json")
        mark_epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$mark_at" +%s 2>/dev/null || echo "")
        if [[ "$mark_state" != away || -z "$mark_epoch" ]] || (( $(date +%s) - mark_epoch < AWAY_SETTLE )); then
            rm -f "$out"
            quiet "staged build waiting; PaintSoftware is in use on the iPad (marker: ${mark_state:-unreadable}) and an install would close it — installs once it has been left"
            return 0
        fi
    fi
    log "Installing ${STAGED_SOURCE_SHA:0:8} (profile to $STAGED_PROFILE_EXPIRATION) on $DEVICE_UUID"
    run_bounded 600 "$out" run_as_user xcrun devicectl device install app --device "$DEVICE_UUID" "$STAGED_APP_PATH" || rc=$?
    if (( rc == 0 )); then
        run_as_user xcrun devicectl device info apps --device "$DEVICE_UUID" --bundle-id "$BUNDLE_ID" > "$out" 2>&1 || rc=$?
        (( rc == 0 )) && ! grep -qF "$BUNDLE_ID" "$out" && rc=1
    fi
    if (( rc != 0 )); then
        log_block "$(tail -15 "$out")"
        rm -f "$out"
        INSTALL_FAILS=$(( ${INSTALL_FAILS:-0} + 1 ))
        save_runtime
        log "VERDICT: WAIT — install failed (exit $rc, $INSTALL_FAILS in a row); retrying next tick"
        (( INSTALL_FAILS == INSTALL_FAIL_NOTIFY )) && notify "installing on the iPad has failed $INSTALL_FAILS times while it was reachable — see resign.log"
        return 0
    fi
    rm -f "$out"

    previous=$LAST_APP_PATH
    LAST_APP_PATH=$STAGED_APP_PATH
    LAST_SOURCE_SHA=$STAGED_SOURCE_SHA
    LAST_PROFILE_EXPIRATION=$STAGED_PROFILE_EXPIRATION
    LAST_PROFILE_CREATION=$STAGED_PROFILE_CREATION
    clear_staged
    save_state || { log "VERDICT: FAIL — installed, but could not write $STATE_FILE"; notify "installed, but could not record it in $STATE_FILE"; return 1; }
    INSTALL_FAILS=""
    QUIET_NOTE=""
    save_runtime
    [[ -n "$previous" && "$previous" != "$LAST_APP_PATH" ]] && remove_build "$previous"
    log "VERDICT: OK — installed ${LAST_SOURCE_SHA:0:8}; profile expires $LAST_PROFILE_EXPIRATION"
}

# ---------------------------------------------------------------- tick

tick() {
    local expiry sign_due=0 staged_exp
    load_keys "$STATE_FILE" "${STATE_KEYS[@]}"
    load_keys "$RUNTIME_FILE" "${RUNTIME_KEYS[@]}"

    # A staged build that can no longer be installed is worthless; drop it and sign again.
    if [[ -n "$STAGED_APP_PATH" ]]; then
        staged_exp=$(iso_to_epoch "$STAGED_PROFILE_EXPIRATION" || echo 0)
        if (( staged_exp - NOW < MIN_INSTALL_LIFE )) || [[ ! -d "$STAGED_APP_PATH" ]]; then
            if [[ $DRY_RUN == 1 ]]; then log "would drop staged build (expires $STAGED_PROFILE_EXPIRATION)"
            else
                local dead=$STAGED_APP_PATH
                log "Dropping staged build $dead (profile $STAGED_PROFILE_EXPIRATION, under an hour left or missing)"
                clear_staged
                save_state || true
                remove_build "$dead"
            fi
        fi
    fi

    expiry=$(newest_expiry)
    if [[ -z "$expiry" ]] || (( expiry - NOW <= DUE_WINDOW )); then
        (( NOW >= ${NEXT_SIGN_AFTER:-0} )) && sign_due=1
    fi
    schedule_wakes

    if [[ $DRY_RUN == 1 ]]; then
        log "newest profile expires ${STAGED_PROFILE_EXPIRATION:-${LAST_PROFILE_EXPIRATION:-never recorded}}; sign due: $sign_due; staged: ${STAGED_APP_PATH:-none}"
        return 0
    fi
    if [[ $sign_due == 0 && -z "$STAGED_APP_PATH" ]]; then
        [[ $IS_ROOT == 1 ]] && log "VERDICT: SKIP — nothing to do; profile expires ${LAST_PROFILE_EXPIRATION:-?}${NEXT_SIGN_AFTER:+, next sign attempt after $(date -r "$NEXT_SIGN_AFTER" '+%m/%d %H:%M')}"
        return 0
    fi
    rotate_log
    if [[ $sign_due == 1 ]]; then
        sign || true
        [[ -n "$STAGED_APP_PATH" ]] && schedule_wakes
    fi
    [[ -n "$STAGED_APP_PATH" ]] && install_staged
    return 0
}

on_exit() {
    local rc=$?
    (( rc != 0 )) && log "VERDICT: FAIL — aborted unexpectedly (exit $rc)"
    true
}

mkdir -p "$CONFIG_DIR"
if [[ $DRY_RUN == 0 && -z "${RESIGN_HOLDS_LOCK:-}" ]]; then
    # lockf holds a kernel lock for the child's life, so a killed holder cannot wedge the next run.
    [[ -e "$LOCK_FILE" ]] || { : > "$LOCK_FILE"; chmod 644 "$LOCK_FILE"; own "$LOCK_FILE"; }
    rc=0
    RESIGN_HOLDS_LOCK=1 lockf -s -t 0 -k "$LOCK_FILE" /bin/bash "$SELF" "$@" || rc=$?
    (( rc == 75 )) && exit 0    # another tick is running; it does the work
    exit $rc
fi
trap on_exit EXIT
tick
