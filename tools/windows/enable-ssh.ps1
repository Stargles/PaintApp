# Enable OpenSSH Server on the Windows laptop so this Mac can build and run the streamer over Tailscale.
# Run ONCE, in PowerShell opened "Run as administrator", on the Windows machine. Idempotent.
$ErrorActionPreference = 'Stop'
$pub = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOAAtezphb370A50Ro+JPZplDcnYc4qaxhMffzrc5mOG claude@julias-macbook-pro paintapp-streamer'

# 1. The server itself (built into Windows 10 1809+ / 11 as an optional feature).
if ((Get-WindowsCapability -Online -Name 'OpenSSH.Server*').State -ne 'Installed') {
  Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
}
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

# 2. Firewall rule for port 22 (the feature usually adds it; make sure).
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
    -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

# 3. PowerShell, not cmd, as the shell an SSH login gets.
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
  -Value "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

# 4. The Mac's public key. Administrator accounts are read from administrators_authorized_keys
#    (which must have exactly these ACLs); a standard account from ~\.ssh\authorized_keys. Write both.
$adminKeys = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
if (-not (Test-Path $adminKeys) -or -not (Select-String -Path $adminKeys -SimpleMatch $pub -Quiet)) {
  Add-Content -Path $adminKeys -Value $pub -Encoding ascii
}
icacls $adminKeys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

$userSsh = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Force -Path $userSsh | Out-Null
$userKeys = Join-Path $userSsh 'authorized_keys'
if (-not (Test-Path $userKeys) -or -not (Select-String -Path $userKeys -SimpleMatch $pub -Quiet)) {
  Add-Content -Path $userKeys -Value $pub -Encoding ascii
}

Restart-Service sshd
Write-Host ""
Write-Host "Done. Tell Claude this username:  $env:USERNAME"
Write-Host "Tailscale IP of this machine:     $(& 'C:\Program Files\Tailscale\tailscale.exe' ip -4 2>$null)"
