# Maintainer notes

Player install instructions are in the root [`README.md`](../README.md).  
Players should download **[GitHub Releases](https://github.com/Nalfey/TetraMaster/releases)** only — not the source tree.

## Creating a release zip

| Script | Purpose |
| --- | --- |
| `build-fused.ps1` | Build `runtime\TetraMaster.exe` from source (requires [LOVE 11.5](https://love2d.org/)). |
| `package-release.ps1` | Create `TetraMaster.zip` for players (includes `runtime\`, excludes server/relay code). |

Typical release flow:

```powershell
.\build\build-fused.ps1 -Release
.\build\package-release.ps1 -Version 1.2
```

Upload the zip to **[GitHub Releases](https://github.com/Nalfey/TetraMaster/releases)**. Mark it as the latest release so players find it easily.

Players do not need LOVE, PowerShell, or anything in this `build/` folder.

## Relay server deploy

These deploy the duel relay on a Linux VM (Oracle, etc.) behind Cloudflare Tunnel.

| Script / file | Purpose |
| --- | --- |
| `vm-prep.sh` | One-time VM bootstrap (Lua, Python venv, cloudflared, firewall). |
| `deploy-relay.ps1` | Upload `relay/` + systemd units; restart relay + ws-bridge. |
| `setup-cloudflare-tunnel.ps1` | Cloudflare login (once), create tunnel, DNS, cloudflared service. |
| `setup-cloudflare-dns.ps1` | Optional: print expected DNS + verify resolution. |
| `setup-cloudflare-tunnel.sh` | Same as tunnel setup, run on the VM (called by `.ps1`). |
| `cloudflared-config.yml` | Template ingress config (WSS → localhost:8080). |
| `tetramaster-*.service` | systemd units for relay, ws-bridge, cloudflared. |

Relay listens on **127.0.0.1** only; clients connect via **wss://relay.tetramasters.uk/** (port 443).
