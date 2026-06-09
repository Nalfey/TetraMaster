param(
    [string]$LoveExe = "C:\Program Files\LOVE\love.exe",
    [switch]$Release
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DistDir = Join-Path $ProjectRoot "dist"
$RuntimeDir = Join-Path $ProjectRoot "runtime"
$StagingDir = Join-Path $env:TEMP "tetramaster-build"
$LoveArchive = Join-Path $DistDir "TetraMaster.love"
$FusedExe = Join-Path $DistDir "TetraMaster.exe"
$LoveDir = Split-Path -Parent $LoveExe

$RuntimeFiles = @(
    "love.dll",
    "lua51.dll",
    "SDL2.dll",
    "OpenAL32.dll",
    "mpg123.dll",
    "msvcp120.dll",
    "msvcr120.dll",
    "license.txt"
)

if (-not (Test-Path $LoveExe)) {
    throw "LOVE not found at '$LoveExe'. Install LOVE 11.5 or pass -LoveExe."
}

$excludeNames = @(
    "build",
    "dist",
    "runtime",
    ".git",
    ".cursor",
    "README.md",
    "README.txt"
)

$excludeFiles = @(
    "TetraMaster.exe",
    "TetraMaster.lua"
)

function Should-CopyPath {
    param([string]$RelativePath)

    foreach ($part in $RelativePath -split "[\\/]") {
        if ($excludeNames -contains $part) {
            return $false
        }
    }

    if ($RelativePath -match "\.love$") {
        return $false
    }

    $leaf = Split-Path $RelativePath -Leaf
    if ($excludeFiles -contains $leaf) {
        return $false
    }

    return $true
}

function Copy-LoveRuntime {
    param(
        [string]$DestinationDir,
        [string]$GameExe,
        [switch]$SkipExeCopy
    )

    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null

    if (-not $SkipExeCopy) {
        Copy-Item $GameExe (Join-Path $DestinationDir "TetraMaster.exe") -Force
    }

    foreach ($file in $RuntimeFiles) {
        $source = Join-Path $LoveDir $file
        if (-not (Test-Path $source)) {
            throw "LOVE runtime file not found: $source"
        }
        Copy-Item $source $DestinationDir -Force
    }
}

Write-Host "Staging game files..."
if (Test-Path $StagingDir) {
    Remove-Item $StagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StagingDir | Out-Null
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

Get-ChildItem $ProjectRoot -Force | ForEach-Object {
    $relative = $_.Name
    if (-not (Should-CopyPath $relative)) {
        return
    }

    $destination = Join-Path $StagingDir $_.Name
    if ($_.PSIsContainer) {
        Copy-Item $_.FullName $destination -Recurse -Force
    }
    else {
        Copy-Item $_.FullName $destination -Force
    }
}

if ($Release) {
    $confPath = Join-Path $StagingDir "conf.lua"
    $conf = Get-Content $confPath -Raw
    $conf = $conf -replace "t\.console\s*=\s*true", "t.console = false"
    Set-Content $confPath $conf -NoNewline
}

Write-Host "Creating TetraMaster.love..."
if (Test-Path $LoveArchive) {
    Remove-Item $LoveArchive -Force
}

$zipPath = [System.IO.Path]::ChangeExtension($LoveArchive, ".zip")
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Compress-Archive -Path (Join-Path $StagingDir "*") -DestinationPath $zipPath -CompressionLevel Optimal
Move-Item $zipPath $LoveArchive -Force

Write-Host "Fusing LOVE runtime with game archive..."
if (Test-Path $FusedExe) {
    Remove-Item $FusedExe -Force
}

$fuseCmd = "copy /b `"$LoveExe`"+`"$LoveArchive`" `"$FusedExe`""
cmd /c $fuseCmd | Out-Null

if (-not (Test-Path $FusedExe)) {
    throw "Fused executable was not created."
}

Write-Host "Copying runtime into dist and runtime folders..."
Copy-LoveRuntime -DestinationDir $DistDir -GameExe $FusedExe -SkipExeCopy
Copy-LoveRuntime -DestinationDir $RuntimeDir -GameExe $FusedExe

Write-Host ""
Write-Host "Build complete:"
Write-Host "  $DistDir"
Write-Host "  $RuntimeDir"
Write-Host ""
Write-Host "This folder is the Windower addon. In FFXI:"
Write-Host "  //lua load TetraMaster"
Write-Host "  //tetramaster play  (or //tm play)"

Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
