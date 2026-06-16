param(
    [string]$RelayHost = "relay.tetramasters.uk"
)

Write-Host "=== Cloudflare DNS for TetraMaster (tunnel mode) ==="
Write-Host ""
Write-Host "After running build\setup-cloudflare-tunnel.ps1, DNS is managed by Cloudflare Tunnel."
Write-Host "Remove any grey-cloud A record for 'relay' if it still points at the Oracle VM IP."
Write-Host ""
Write-Host "Expected record (created by cloudflared tunnel route dns):"
Write-Host "  Type:     CNAME"
Write-Host "  Name:     relay"
Write-Host "  Target:   <tunnel-id>.cfargotunnel.com"
Write-Host "  Proxy:    Proxied (orange cloud)"
Write-Host ""
Write-Host "Clients use wss://$RelayHost/ automatically (port 443)."
Write-Host "Raw TCP :19876 is no longer exposed publicly."
Write-Host ""
Write-Host "Verify:"
Write-Host "  Test-NetConnection $RelayHost -Port 443"
Write-Host "  nslookup $RelayHost"
Write-Host ""

try {
    $resolved = [System.Net.Dns]::GetHostAddresses($RelayHost) | Select-Object -First 1
    Write-Host "DNS check: $RelayHost -> $($resolved.IPAddressToString)"
} catch {
    Write-Host "DNS check: $RelayHost not resolved yet."
}
