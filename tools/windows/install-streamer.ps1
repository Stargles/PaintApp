<#
.SYNOPSIS
  Idempotent installer for PaintStreamer (STREAM.md section 4.3/section 4.1). Run as Administrator,
  normally over SSH as PC: this script assumes it is NOT the account the app will run
  as (see the AppDir note below).

.DESCRIPTION
  1. Checks the .NET 8 SDK and GStreamer are present (does not install them - they
     already are on this laptop; a machine missing them gets a clear message instead
     of a half-attempted winget install that needs an interactive session anyway).
  2. Publishes Streamer.Tray (framework-dependent, win-x64) from -SourceDir into
     $AppDir\app.
  3. Ensures the firewall rule for port 47301 admits Tailscale AND any RFC1918 LAN
     (TODO (98)) - a coarse, static superset; AdmissionPolicy.cs is the precise,
     live per-connection gate, which a firewall rule cannot be since it can't know
     which subnet this laptop's NIC is actually on at any given moment.
  4. TODO (99): a Start Menu shortcut and a desktop shortcut to Streamer.Tray.exe -
     "just like any normal computer program, clicking the app launches the program."
  5. Registers (or re-registers) the "PaintStreamer" Scheduled Task to run the
     published exe AS KEVIN, interactively, WITH NO TRIGGER (TODO (99): "it shouldn't
     start up every time the computer is started") - it exists purely as the
     mechanism `tools/windows/streamer-remote.sh start` uses to launch the app inside
     kevin's interactive session from a non-interactive SSH connection (STREAM.md
     section 4.3: an SSH session is a non-interactive window station and neither the
     app nor gst-launch-1.0 can capture from there); the shortcut and the task launch
     the identical exe with no arguments, and Streamer.Tray's own named-mutex guard
     (SingleInstanceGuard) is what stops the two from ever running at once.

.NOTES
  AppDir is an EXPLICIT path, not %LOCALAPPDATA%. Reason: this script runs as PC over
  SSH, so $env:LOCALAPPDATA here resolves to PC's own profile
  (C:\Users\PC\AppData\Local), not kevin's - even though the app is being installed
  FOR kevin. C:\Users\kevin\AppData\Local\PaintStreamer is spelled out explicitly so
  the files land where kevin's own session (which DOES correctly see %LOCALAPPDATA%
  as its own, once the exe is actually running as kevin) expects them: the app's own
  runtime code resolves this same path via Environment.SpecialFolder at run time,
  which is correct because by then the process really is kevin's.
#>
param(
    [string]$SourceDir = "C:\Users\PC\src\streamer",
    [string]$AppDir = "C:\Users\kevin\AppData\Local\PaintStreamer",
    [string]$DotnetExe = "C:\dotnet\dotnet.exe",
    [string]$GstBinDir = "C:\Program Files\gstreamer\1.0\msvc_x86_64\bin",
    [int]$Port = 47301
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host "REFUSE: $msg" -ForegroundColor Red
    exit 1
}

Write-Host "== PaintStreamer installer =="

# ---- 1. Preconditions - check, do not install (STREAM.md: "the script should check
#         for them and say what to do if missing rather than installing"). ----
if (-not (Test-Path $DotnetExe)) {
    Fail ".NET SDK not found at $DotnetExe. Install the .NET 8 SDK, or pass -DotnetExe with its path."
}
$gstLaunch = Join-Path $GstBinDir "gst-launch-1.0.exe"
if (-not (Test-Path $gstLaunch)) {
    Fail "GStreamer not found at $gstLaunch. Install GStreamer 1.22+ MSVC x86_64 (with all plugins), or pass -GstBinDir."
}
$gstInspect = Join-Path $GstBinDir "gst-inspect-1.0.exe"
if (-not (Test-Path $gstInspect)) {
    Fail "gst-inspect-1.0.exe not found beside gst-launch-1.0.exe in $GstBinDir - GStreamer install looks incomplete."
}
if (-not (Test-Path $SourceDir)) {
    Fail "Source not found at $SourceDir. Ship it first: tar cz -C <worktree> streamer | ssh ... 'tar xz -C C:\Users\PC\src'"
}
Write-Host "  .NET SDK:    OK ($DotnetExe)"
Write-Host "  GStreamer:   OK ($GstBinDir)"
Write-Host "  Source:      OK ($SourceDir)"

# ---- 2. Publish (framework-dependent - the .NET 8 runtime is already on this box) ----
$trayProj = Join-Path $SourceDir "Streamer.Tray\Streamer.Tray.csproj"
if (-not (Test-Path $trayProj)) { Fail "Streamer.Tray.csproj not found under $SourceDir" }
$publishDir = Join-Path $AppDir "app"
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

Write-Host "== Publishing Streamer.Tray to $publishDir =="
& $DotnetExe publish $trayProj -c Release -r win-x64 --self-contained false -o $publishDir
if ($LASTEXITCODE -ne 0) { Fail "dotnet publish failed (exit $LASTEXITCODE)" }

$exePath = Join-Path $publishDir "Streamer.Tray.exe"
if (-not (Test-Path $exePath)) { Fail "Publish succeeded but $exePath does not exist - check the publish output above" }
Write-Host "  Published: $exePath"

# ---- 3. Firewall rule (idempotent; Tailscale + RFC1918 LAN per STREAM.md section 4.3/TODO (98)) ----
# A static, coarse allow-list: it cannot know which of these subnets the laptop's NIC is
# actually on right now (or whether it moves to a different one mid-session), so
# AdmissionPolicy.cs re-checks every connection against the laptop's LIVE NIC data - this
# rule only has to be at least as permissive as that check ever needs.
$ruleName = "PaintStreamer-In-TCP"
$remoteAddresses = @("100.64.0.0/10", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if (-not $existingRule) {
    Write-Host "== Creating firewall rule $ruleName (TCP $Port, remote $($remoteAddresses -join ', ')) =="
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP `
        -LocalPort $Port -RemoteAddress $remoteAddresses -Action Allow | Out-Null
} else {
    Write-Host "== Updating firewall rule $ruleName remote scope (idempotent - re-applies every run) =="
    Set-NetFirewallRule -DisplayName $ruleName -RemoteAddress $remoteAddresses | Out-Null
}

# ---- 4. Start Menu + desktop shortcuts (TODO (99): "just like any normal computer program") ----
# $env:ProgramData is machine-wide (not per-user, unlike $env:LOCALAPPDATA above), so it
# resolves the same regardless of which account this script runs as - no explicit-path trap
# here. kevin's own Desktop still needs the explicit path, same reason as $AppDir.
Write-Host "== Creating shortcuts to $exePath =="
$shell = New-Object -ComObject WScript.Shell
$shortcutTargets = @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\PaintStreamer.lnk",  # all users' Start Menu
    "C:\Users\kevin\Desktop\PaintStreamer.lnk"                                    # kevin's own desktop
)
foreach ($lnkPath in $shortcutTargets) {
    $shortcut = $shell.CreateShortcut($lnkPath)
    $shortcut.TargetPath = $exePath
    $shortcut.WorkingDirectory = Split-Path $exePath
    $shortcut.Description = "PaintStreamer - stream this computer's screen to PaintApp"
    $shortcut.Save()
    Write-Host "  $lnkPath"
}

# ---- 5. Scheduled Task, running AS KEVIN, interactively, WITH NO TRIGGER (TODO (99)) ----
# On-demand only: nothing fires it automatically at logon or any other time. It exists
# solely so `streamer-remote.sh start` can reach into kevin's interactive session from a
# non-interactive SSH connection (Start-ScheduledTask), exactly as the shortcut's own
# double-click does by hand - see streamer.ps1's "start" doc comment.
$taskName = "PaintStreamer"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "== Removing existing '$taskName' task to re-register cleanly =="
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

Write-Host "== Registering Scheduled Task '$taskName' (User=kevin, LogonType=Interactive, no trigger) =="
$action = New-ScheduledTaskAction -Execute $exePath
$principal = New-ScheduledTaskPrincipal -UserId "kevin" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings | Out-Null

Write-Host "== Verifying =="
Get-ScheduledTask -TaskName $taskName | Format-List TaskName, State
Write-Host ""
Write-Host "Install complete. The artist starts it by double-clicking the Start Menu or desktop"
Write-Host "shortcut. To start it remotely (SSH, no one at the keyboard): tools/windows/streamer.ps1 start"
