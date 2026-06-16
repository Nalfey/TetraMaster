param(
    [string]$SshHost = "ubuntu@145.241.251.131",
    [string]$KeyPath = "$env:USERPROFILE\Desktop\TetraMaster\Oracle\ssh-key-2026-06-16.key",
    [string]$RelayHostname = "relay.tetramasters.uk",
    [string]$TunnelName = "tetramaster-relay",
    [switch]$LoginOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$relayDir = Join-Path $root "relay"
$key = Resolve-Path $KeyPath

$sshArgs = @("-i", $key, "-o", "StrictHostKeyChecking=accept-new", "-t")
$scpArgs = @("-i", $key, "-o", "StrictHostKeyChecking=accept-new")

if ($LoginOnly) {
    Write-Host "Starting Cloudflare login on VM (open URL in browser when prompted)..."
    ssh @sshArgs $SshHost "cloudflared tunnel login"
    exit $LASTEXITCODE
}

Write-Host "Uploading relay + tunnel files..."
scp @scpArgs `
    (Join-Path $relayDir "relay.lua") `
    (Join-Path $relayDir "protocol.lua") `
    (Join-Path $relayDir "ws_bridge.py") `
    (Join-Path $relayDir "requirements.txt") `
    "${SshHost}:/opt/tetramaster/bin/"

scp @scpArgs `
    (Join-Path $PSScriptRoot "tetramaster-relay.service") `
    (Join-Path $PSScriptRoot "tetramaster-ws-bridge.service") `
    (Join-Path $PSScriptRoot "tetramaster-cloudflared.service") `
    (Join-Path $PSScriptRoot "setup-cloudflare-tunnel.sh") `
    "${SshHost}:/tmp/"

Write-Host "Running tunnel setup on VM..."
$remote = @"
set -euo pipefail
chmod +x /tmp/setup-cloudflare-tunnel.sh
sudo luarocks install luasocket 2>/dev/null || true
export TM_RELAY_HOSTNAME='$RelayHostname'
export TM_TUNNEL_NAME='$TunnelName'
bash /tmp/setup-cloudflare-tunnel.sh
"@

ssh @sshArgs $SshHost $remote
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Tunnel setup did not complete (exit $LASTEXITCODE)."
    if ($LASTEXITCODE -eq 2) {
        Write-Host "Run Cloudflare login first:"
        Write-Host "  powershell -File build\setup-cloudflare-tunnel.ps1 -LoginOnly"
    }
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Tunnel setup finished."
Write-Host "Clients connect via wss://$RelayHostname/ (automatic for //tm relayhost default)."
Write-Host ""
Write-Host "Verify from PowerShell:"
Write-Host "  Test-NetConnection $RelayHostname -Port 443"
Write-Host ""
Write-Host "If setup failed with exit 2, run login first:"
Write-Host "  powershell -File build\setup-cloudflare-tunnel.ps1 -LoginOnly"
