<#
.SYNOPSIS
    Fetch a simulator screenshot from the Mac and save it locally.

.DESCRIPTION
    1. SSHs to the Mac to take a screenshot of the session's simulator
    2. SCPs the screenshot back to Windows
    3. Prints the local file path (for the AI to read with the Read tool)

.PARAMETER SessionId
    The session ID whose simulator should be screenshotted.

.PARAMETER OutputDir
    Local directory to save the screenshot. Defaults to $env:TEMP\paintapp-screenshots.

.EXAMPLE
    .\screenshot_fetch.ps1 my-session
    .\screenshot_fetch.ps1 my-session C:\tmp\screenshots
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SessionId,

    [string]$OutputDir = "$env:TEMP\paintapp-screenshots"
)

$MacUser = "juliapark"
$MacHost = "100.70.148.78"
$SshTarget = "$MacUser@$MacHost"

# Sanitize session ID for use as filename
$SafeSessionId = $SessionId -replace '[^a-zA-Z0-9_\-]', '_'

# Create output directory
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "Taking screenshot of simulator for session '$SessionId'..."

# Step 1: SSH to Mac and take the screenshot
$MacTmpPath = "/tmp/paintapp-screenshots/${SafeSessionId}_fetch.png"
$sshCommand = "bash ~/PaintApp/deploy/mac/screenshot.sh `"$SessionId`" `"$MacTmpPath`""

try {
    $remotePath = ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new $SshTarget $sshCommand 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Screenshot failed on Mac: $remotePath"
        exit 1
    }
    # The script outputs the path on success
    $remotePath = $remotePath.Trim()
    Write-Host "Remote screenshot saved: $remotePath"
} catch {
    Write-Error "SSH failed: $_"
    exit 1
}

# Step 2: SCP the file back to Windows
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$localPath = Join-Path $OutputDir "${SafeSessionId}_${timestamp}.png"

Write-Host "Fetching screenshot via SCP..."
try {
    scp -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new "${SshTarget}:${remotePath}" $localPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "SCP failed"
        exit 1
    }
} catch {
    Write-Error "SCP failed: $_"
    exit 1
}

# Step 3: Clean up the remote file
ssh -o ConnectTimeout=10 $SshTarget "rm -f '$remotePath'" 2>$null

# Step 4: Print the local path for the AI to read
Write-Host ""
Write-Host "Screenshot saved locally: $localPath"
Write-Host "Use the Read tool to view: $localPath"
