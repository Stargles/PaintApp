# Auto-resign

The owner's iPad runs PaintApp under a free Apple developer account, whose provisioning profile lasts
seven days. When it lapses the iPad says *"PaintApp is no longer available"*. `tools/resign/` keeps it
alive with no one at either machine.

## Shape

Signing and installing are two stages over one state file, `~/.config/paintapp/resign_state`:

| stage | needs | does |
|---|---|---|
| **sign** | the Mac and Xcode's Apple ID session — never the iPad | when the newest profile (staged, else installed) is expired or within an hour of it: fetch (best-effort), pick the source, build Release for `generic/platform=iOS` with `-allowProvisioningUpdates`, check the profile advanced and the signature verifies, copy the app to `~/PaintWork/device-<sha8>-Release-<profile creation>/`, record `STAGED_*` |
| **install** | the iPad listed `available` by `devicectl list devices` **and PaintSoftware not in use on it** | install the staged app, confirm the bundle is on the device, promote `STAGED_*` to `LAST_*`, delete the superseded build folder |

**Never install over an app in use (Nov 21, refined Nov 27).** An install terminates the app and loses
unsaved strokes. `devicectl device info processes` lists every live process and carries only a pid and a
path (MEASURED on iOS 26, `--json-output`: `executable`, `processIdentifier`; nothing on foreground or
suspended), so an app the owner left stays listed for hours and cannot be judged by the list. Not listed:
install. Listed: the stage copies the app's own `Library/Application Support/CrashWatch/foreground.marker`
(`devicectl device copy from`, `appDataContainer`; written by `UncleanExitWatch` — `foreground` while the
scene is active, `away` once it is in the background) and installs only if it says `away` and is at least
`AWAY_SETTLE` (120 s) old, so the app's save on leaving the foreground (`ScenePhaseSaveGate`) has finished.
Foreground, a fresh `away`, a missing marker, a failed copy, or a failed or implausible process query defers
(quiet `WAIT` line, nothing changed). A suspended app loses nothing because it saved on the way out; an app
killed while `foreground` is not listed, so it never blocks.

`LAST_*` always names what is installed on the iPad; it is written only after an install succeeds, and
every write is a sibling temp file renamed into place.

**Source.** The build advances only to a descendant of the installed source: `origin/main` when it
contains `LAST_SOURCE_SHA`, the installed commit while main is behind it, and nothing at all when the
histories are unrelated or the commit is missing (fail closed). A failed fetch rebuilds the installed
commit, which is always local. A manual install from a branch must import that commit into
`~/PaintApp` and update all four `LAST_*` fields atomically — never before the install succeeds.

**Triggers.**
- User LaunchAgent `com.paintapp.resign-agent` — every 300 s and at login. A tick with nothing due and
  nothing staged reads two small files and exits: no device query, no log line.
- Root LaunchDaemon `com.paintapp.resign` — hourly and at boot. Same tick, plus the one thing only root
  can do: `pmset` wakes an hour before expiry, two minutes after it (when the portal will mint) and an
  hour after that, or hourly while expired.
- A `lockf` kernel lock serialises them; a killed holder releases it.

**Portal.** The free portal mints a new profile only once the old one has expired (MEASURED 2026-09-23,
09-30, 11-20). A same-profile answer before expiry is a quiet wait with no rebuild until two minutes
past expiry; the same answer after expiry is a failure. The generic destination needs the iPad already
registered with the team; on *"no devices from which to generate a provisioning profile"* the sign
retries with the iPad named and `-allowProvisioningDeviceRegistration`, which needs it unlocked.

**Notifications** go to the owner only when he must act: no Apple ID session, keychain or codesign
key unusable, dirty or unrelated source, a stale profile after expiry, any sign failure once the
installed profile is dead, or twelve install failures in a row while the iPad was reachable. Never for
an asleep, locked or absent iPad. At most one every three hours.

## The gap that cannot be closed

From the moment a profile expires until the Mac is on **and** the iPad is reachable, the app does not
open. If the Mac is awake (or wakes on the scheduled `pmset` event) a new profile is staged within
minutes of expiry, and installed within five minutes of the iPad appearing. If the Mac is off at
expiry nothing runs; at boot `RunAtLoad` signs at once. A Mac that is asleep with its lid closed on
battery may ignore the wake. Both stages run in the owner's login session (keychain, Xcode's Apple ID),
so after a reboot nothing signs until he logs in; a locked screen is fine.

## Operating it

```bash
tools/resign/install.sh                 # pin the script, point the daemon's shim at it, load the agent
bash tools/resign/test-resign.sh        # 14 behavioural cases with fake xcodebuild/devicectl/security
~/.config/paintapp/bin/resign.sh --dry-run   # what a tick would do now
```

`install.sh` copies `tools/resign/resign.sh` to `~/.config/paintapp/bin/resign.sh`, so moving `main`
never changes the script under a running job; re-run it after changing the script. The daemon's plist
names `~/PaintApp/deploy/resign.sh`, which `install.sh` rewrites as a one-line shim to the pinned copy,
so the plist never needs `sudo` again. Log: `~/.config/paintapp/resign.log`, one `VERDICT:` line per
outcome (`OK`, `STAGED`, `WAIT`, `SKIP`, `FAIL`), trimmed at 2 MB.

## History

Broke about ten times before 2026-11-20, every time because one run needed network, the Apple ID, the
iPad and an unlocked iPad at once: iPad unreachable (16 runs), `git fetch` failed (10), `xcodebuild
clean` against the named iPad timed out waiting for it to unlock (8), install failed (8), same profile
returned (7). Earlier fixes that the current shape keeps: clean and build share identical arguments or
the profile is copied in without a new CodeSign seal (2026-10-22); renewal never downgrades the
installed source (2026-10-28).
