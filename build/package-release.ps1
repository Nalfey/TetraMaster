param(
    [string]$Version = "",
    [string]$OutputDir = "$env:USERPROFILE\Desktop"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AddonName = "TetraMaster"
$StagingDir = Join-Path $env:TEMP "tetramaster-release"
$RuntimeExe = Join-Path $ProjectRoot "runtime\TetraMaster.exe"

$ExcludeDirNames = @(
    "sync",
    ".git",
    ".cursor",
    "dist",
    "build"
)

$ExcludeFileNames = @(
    "TetraMaster.exe"
)

if (-not (Test-Path $RuntimeExe)) {
    throw "runtime\TetraMaster.exe not found. Run build\build-fused.ps1 -Release first."
}

function Should-IncludeTopLevel {
    param(
        [string]$Name,
        [bool]$IsContainer
    )

    if ($ExcludeDirNames -contains $Name) {
        return $false
    }

    if (-not $IsContainer -and $ExcludeFileNames -contains $Name) {
        return $false
    }

    if (-not $IsContainer -and $Name -like "*.love") {
        return $false
    }

    return $true
}

if (Test-Path $StagingDir) {
    Remove-Item $StagingDir -Recurse -Force
}

$PackageRoot = Join-Path $StagingDir $AddonName
New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null

Get-ChildItem $ProjectRoot -Force | ForEach-Object {
    if (-not (Should-IncludeTopLevel $_.Name $_.PSIsContainer)) {
        return
    }

    $destination = Join-Path $PackageRoot $_.Name
    if ($_.PSIsContainer) {
        Copy-Item $_.FullName $destination -Recurse -Force
    }
    else {
        Copy-Item $_.FullName $destination -Force
    }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$zipName = if ($Version) {
    "$AddonName-$Version.zip"
}
else {
    "$AddonName.zip"
}

$zipPath = Join-Path $OutputDir $zipName
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Write-Host "Creating release archive..."
Compress-Archive -Path $PackageRoot -DestinationPath $zipPath -CompressionLevel Optimal

Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Release package created:"
Write-Host "  $zipPath"
Write-Host ""
Write-Host "Extract the zip so you have:"
Write-Host "  <Windower>\addons\TetraMaster\"
