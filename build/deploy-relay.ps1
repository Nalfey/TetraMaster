param(
    [string]$SshHost = "ubuntu@145.241.251.131",
    [string]$KeyPath = "$env:USERPROFILE\Desktop\TetraMaster\Oracle\ssh-key-2026-06-16.key"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$relayDir = Join-Path $root "relay"
$key = Resolve-Path $KeyPath

$sshArgs = @("-i", $key, "-o", "StrictHostKeyChecking=accept-new")
$scpArgs = @("-i", $key, "-o", "StrictHostKeyChecking=accept-new")

Write-Host "Uploading relay files..."
scp @scpArgs `
    (Join-Path $relayDir "relay.lua") `
    (Join-Path $relayDir "protocol.lua") `
    (Join-Path $relayDir "ws_bridge.py") `
    (Join-Path $relayDir "requirements.txt") `
    "${SshHost}:/opt/tetramaster/bin/"

scp @scpArgs `
    (Join-Path $PSScriptRoot "tetramaster-relay.service") `
    (Join-Path $PSScriptRoot "tetramaster-ws-bridge.service") `
    "${SshHost}:/tmp/"

Write-Host "Installing relay services (localhost TCP + ws bridge)..."
$remote = @"
set -euo pipefail
sudo luarocks install luasocket
sudo apt-get install -y -qq python3-venv python3-pip
if [ ! -d /opt/tetramaster/venv ]; then
  python3 -m venv /opt/tetramaster/venv
fi
/opt/tetramaster/venv/bin/pip install -q -r /opt/tetramaster/bin/requirements.txt
sudo mv /tmp/tetramaster-relay.service /etc/systemd/system/tetramaster-relay.service
sudo mv /tmp/tetramaster-ws-bridge.service /etc/systemd/system/tetramaster-ws-bridge.service
sudo systemctl daemon-reload
sudo systemctl enable tetramaster-relay tetramaster-ws-bridge
sudo systemctl restart tetramaster-relay tetramaster-ws-bridge
sleep 1
sudo systemctl --no-pager status tetramaster-relay tetramaster-ws-bridge
"@

ssh @sshArgs $SshHost $remote

Write-Host ""
Write-Host "Relay deployed on localhost:19876 + ws bridge :8080 (Cloudflare Tunnel only)."
Write-Host "Run build\setup-cloudflare-tunnel.ps1 to expose wss://relay.tetramasters.uk/"
