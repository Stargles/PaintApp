<#
.SYNOPSIS
  Drives the PaintStreamer Scheduled Task from SSH (STREAM.md section 4.3/section 4.1, deliverable 5).

.DESCRIPTION
  start   - Start-ScheduledTask; the task's LogonType=Interactive means this launches
            the exe inside kevin's already-open console session 1, not this SSH
            session's own non-interactive window station.
  stop    - Stop-ScheduledTask, with a fallback Stop-Process if the exe outlives it.
  status  - task state + the running process (name, session id, CPU) if any.
  log [n] - tail the last n lines (default 50) of log.txt.
  sources - runs --list-sources TWO ways for comparison: once directly over this SSH
            session (which, being non-interactive, sees the 1024x768 "WinDisc"
            placeholder - proof of the session point), and once via a temporary
            Scheduled Task in kevin's own session (which sees the real monitor and
            real windows) whose output is read back from log.txt.
  deploy  - assumes source already copied to -SourceDir (the Mac-side
            streamer-remote.sh does the tar/scp); re-runs install-streamer.ps1
            (idempotent: republish + firewall + re-register) then restarts the task.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("start", "stop", "status", "log", "sources", "deploy")]
    [string]$Command,

    [Parameter(Position = 1)]
    [int]$Lines = 50,

    [string]$SourceDir = "C:\Users\PC\src\streamer",
    [string]$AppDir = "C:\Users\kevin\AppData\Local\PaintStreamer",
    [int]$Port = 47301
)

$ErrorActionPreference = "Stop"
$TaskName = "PaintStreamer"
$LogPath = Join-Path $AppDir "log.txt"
$ExePath = Join-Path (Join-Path $AppDir "app") "Streamer.Tray.exe"

function Show-Status {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "Task '$TaskName' is not registered. Run install-streamer.ps1 first."
        return
    }
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host "Task state:      $($task.State)"
    Write-Host "Last run:        $($info.LastRunTime)"
    Write-Host "Last result:     $($info.LastTaskResult)  (0 = still running or last run OK)"
    $procs = Get-Process -Name "Streamer.Tray" -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Select-Object Id, SessionId, CPU, StartTime | Format-Table -AutoSize
    } else {
        Write-Host "No Streamer.Tray.exe process is currently running."
    }
}

# Found live 2026-09-17 (the (98)/(99) bring-up): the FIRST time a given build of the exe
# opens its listening socket, Windows Firewall auto-creates a paired "TCP/UDP Query
# User{GUID}<exe path>" rule pair with Action=Block, scoped to that exact program path -
# the interactive "Windows Defender Firewall has blocked some features of this app"
# prompt's answer, or its default with nobody at the keyboard (both the scheduled task and
# streamer-remote.sh run headlessly). A per-program Block rule wins over
# install-streamer.ps1's port-scoped Allow rule regardless of remote address, so every
# connection is silently dropped - logged DROP in pfirewall.log against this exe's PID,
# with the Allow rule and `netstat` both looking completely correct, since the blocking
# rule is filed under the program, not the port. And it is NOT a one-time thing: a plain
# `dotnet publish` embeds a fresh MVID into the PE file every build even with no source
# change, so Windows treats each republish as a new, unvetted binary and can re-create the
# block the next time it first listens - install-streamer.ps1's own cleanup (which runs
# before the freshly published exe has ever started) cannot catch that one. Call this
# after every launch, not just after install.
function Remove-StaleFirewallBlock {
    Get-NetFirewallApplicationFilter | Where-Object { $_.Program -eq $ExePath } | ForEach-Object {
        $rule = $_ | Get-NetFirewallRule
        if ($rule.Action -eq "Block") {
            Write-Host "== Removing Windows Firewall's auto-created Block rule '$($rule.DisplayName)' for $ExePath =="
            $rule | Remove-NetFirewallRule
        }
    }
}

switch ($Command) {
    "start" {
        Start-ScheduledTask -TaskName $TaskName
        Start-Sleep -Seconds 2
        Remove-StaleFirewallBlock
        Show-Status
    }
    "stop" {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $lingering = Get-Process -Name "Streamer.Tray" -ErrorAction SilentlyContinue
        if ($lingering) {
            Write-Host "Process outlived Stop-ScheduledTask; killing directly."
            $lingering | Stop-Process -Force
        }
        Show-Status
    }
    "status" {
        Show-Status
    }
    "log" {
        if (-not (Test-Path $LogPath)) {
            Write-Host "No log yet at $LogPath"
        } else {
            Get-Content -Path $LogPath -Tail $Lines
        }
    }
    "sources" {
        Write-Host "=== Direct over this SSH session (non-interactive window station) ==="
        Write-Host "--- expect the fake 1024x768 'WinDisc' placeholder here, not the real desktop ---"
        & $ExePath --list-sources
        Write-Host ""
        Write-Host "=== Via a one-off Scheduled Task in kevin's own interactive session ==="
        $tmpTask = "PaintStreamerListSourcesOnce"
        Get-ScheduledTask -TaskName $tmpTask -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
        $before = 0
        if (Test-Path $LogPath) { $before = (Get-Item $LogPath).Length }
        $action = New-ScheduledTaskAction -Execute $ExePath -Argument "--list-sources"
        $principal = New-ScheduledTaskPrincipal -UserId "kevin" -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $tmpTask -Action $action -Principal $principal | Out-Null
        Start-ScheduledTask -TaskName $tmpTask
        $deadline = (Get-Date).AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 500
            $state = (Get-ScheduledTask -TaskName $tmpTask).State
        } while ($state -eq "Running" -and (Get-Date) -lt $deadline)
        Start-Sleep -Seconds 1  # let the log flush
        Unregister-ScheduledTask -TaskName $tmpTask -Confirm:$false
        if (Test-Path $LogPath) {
            $stream = [System.IO.File]::Open($LogPath, 'Open', 'Read', 'ReadWrite')
            $stream.Seek($before, 'Begin') | Out-Null
            $reader = New-Object System.IO.StreamReader($stream)
            $reader.ReadToEnd()
            $reader.Close()
        } else {
            Write-Host "No log produced - check the task ran (state was: $state)"
        }
    }
    "deploy" {
        Write-Host "=== deploy: stopping the running exe before publish (locked-file publish failures) ==="
        # install-streamer.ps1's dotnet publish overwrites the exe/dlls in place, so the
        # currently-running process must be dead FIRST - publishing over a locked file
        # retries for ~10s and then fails outright (hit this for real: MSB3027 "Could
        # not copy ... Streamer.Tray.dll ... Exceeded retry count of 10").
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Get-Process -Name "Streamer.Tray" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500

        Write-Host "=== deploy: re-publishing from $SourceDir and restarting the task ==="
        & (Join-Path $PSScriptRoot "install-streamer.ps1") -SourceDir $SourceDir -AppDir $AppDir -Port $Port
        Start-ScheduledTask -TaskName $TaskName
        Start-Sleep -Seconds 2
        # The just-published exe is a new binary (fresh MVID every build - see
        # Remove-StaleFirewallBlock's comment), so this is its first-ever listen and
        # Windows Firewall may only now decide to auto-block it, even though
        # install-streamer.ps1 already cleaned up whatever block rule predated this build.
        Remove-StaleFirewallBlock
        Show-Status
    }
}
