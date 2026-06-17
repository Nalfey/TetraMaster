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
.\build\package-release.ps1 -Version 1.1.6
```

Upload the zip to **[GitHub Releases](https://github.com/Nalfey/TetraMaster/releases)**. Mark it as the latest release so players find it easily.

Players do not need LOVE, PowerShell, or anything in this `build/` folder.
