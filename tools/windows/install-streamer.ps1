<#
.SYNOPSIS
  Idempotent installer for PaintStreamer (STREAM.md §4.3/§4.1). Run as Administrator,
  normally over SSH as PC: this script assumes it is NOT the account the app will run
  as (see the AppDir note below).

.DESCRIPTION
  1. Checks the .NET 8 SDK and GStreamer are present (does not install them — they
     already are on this laptop; a machine missing them gets a clear message instead
     of a half-attempted winget install that needs an interactive session anyway).
  2. Publishes Streamer.Tray (framework-dependent, win-x64) from -SourceDir into
     $AppDir\app.
  3. Ensures the Tailscale-only firewall rule for port 47301 exists.
  4. Registers (or re-registers) the "PaintStreamer" Scheduled Task to run the
     published exe AS KEVIN, interactively, at logon — so it can actually see the
     desktop (STREAM.md §4.3: an SSH session is a non-interactive window station and
     neither the app nor gst-launch-1.0 can capture from there).

.NOTES
  AppDir is an EXPLICIT path, not %LOCALAPPDATA%. Reason: this script runs as PC over
  SSH, so $env:LOCALAPPDATA here resolves to PC's own profile
  (C:\Users\PC\AppData\Local), not kevin's — even though the app is being installed
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

# ---- 1. Preconditions — check, do not install (STREAM.md: "the script should check
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
    Fail "gst-inspect-1.0.exe not found beside gst-launch-1.0.exe in $GstBinDir — GStreamer install looks incomplete."
}
if (-not (Test-Path $SourceDir)) {
    Fail "Source not found at $SourceDir. Ship it first: tar cz -C <worktree> streamer | ssh ... 'tar xz -C C:\Users\PC\src'"
}
Write-Host "  .NET SDK:    OK ($DotnetExe)"
Write-Host "  GStreamer:   OK ($GstBinDir)"
Write-Host "  Source:      OK ($SourceDir)"

# ---- 2. Publish (framework-dependent — the .NET 8 runtime is already on this box) ----
$trayProj = Join-Path $SourceDir "Streamer.Tray\Streamer.Tray.csproj"
if (-not (Test-Path $trayProj)) { Fail "Streamer.Tray.csproj not found under $SourceDir" }
$publishDir = Join-Path $AppDir "app"
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

Write-Host "== Publishing Streamer.Tray to $publishDir =="
& $DotnetExe publish $trayProj -c Release -r win-x64 --self-contained false -o $publishDir
if ($LASTEXITCODE -ne 0) { Fail "dotnet publish failed (exit $LASTEXITCODE)" }

$exePath = Join-Path $publishDir "Streamer.Tray.exe"
if (-not (Test-Path $exePath)) { Fail "Publish succeeded but $exePath does not exist — check the publish output above" }
Write-Host "  Published: $exePath"

# ---- 3. Firewall rule (idempotent; Tailscale range only per STREAM.md §4.3) ----
$ruleName = "PaintStreamer-In-TCP"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if (-not $existingRule) {
    Write-Host "== Creating firewall rule $ruleName (TCP $Port, remote 100.64.0.0/10) =="
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP `
        -LocalPort $Port -RemoteAddress 100.64.0.0/10 -Action Allow | Out-Null
} else {
    Write-Host "  Firewall rule $ruleName already exists — left as is."
}

# ---- 4. Scheduled Task, running AS KEVIN, interactively, at logon ----
$taskName = "PaintStreamer"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "== Removing existing '$taskName' task to re-register cleanly =="
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

Write-Host "== Registering Scheduled Task '$taskName' (User=kevin, LogonType=Interactive) =="
$action = New-ScheduledTaskAction -Execute $exePath
$principal = New-ScheduledTaskPrincipal -UserId "kevin" -LogonType Interactive -RunLevel Limited
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "kevin"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Trigger $trigger -Settings $settings | Out-Null

Write-Host "== Verifying =="
Get-ScheduledTask -TaskName $taskName | Format-List TaskName, State
Write-Host ""
Write-Host "Install complete. Start it now with: tools/windows/streamer.ps1 start"
Write-Host "(the AtLogOn trigger only fires on the NEXT logon — 'start' runs it immediately"
Write-Host " against kevin's already-open session 1, which is the same mechanism.)"
