<#
.SYNOPSIS
    Package MaaCore and its runtime into a launcher-consumable SDK zip.

.DESCRIPTION
    The SDK layout is:

        MaaCore-sdk-windows-x64-<version>/
          bin/       MaaCore.dll, MaaCore.pdb, MaaUtils.dll and runtime DLLs
          include/   public MaaCore API headers (AsstCaller.h, ...)
          README.md  integration notes
          LICENSE.md

    The CUDA execution provider (onnxruntime_providers_cuda.dll, ~170 MB) is omitted by
    default; DirectML is kept for GPU inference.

.EXAMPLE
    powershell -File .\tools\package-sdk.ps1
#>
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$BuildDir = "build-standalone",
    [string]$Config = "RelWithDebInfo",
    [string]$OutputDir = "",
    [string]$Version = "",
    [string]$Target = "windows-x64",
    [switch]$IncludeCuda
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RepoRoot "dist"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = git -C $RepoRoot describe --tags --always --dirty 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Version)) {
        $Version = "dev"
    }
}
$Version = $Version.Trim() -replace '[^\w.\-+]', '-'

$buildBin = Join-Path $RepoRoot (Join-Path $BuildDir "bin\$Config")
$dllPath = Join-Path $buildBin "MaaCore.dll"
$pdbPath = Join-Path $buildBin "MaaCore.pdb"
$maautilsPath = Join-Path $buildBin "MaaUtils.dll"

foreach ($path in @($dllPath, $maautilsPath)) {
    if (-not (Test-Path $path)) {
        throw "Build output not found: $path. Run tools/build-maacore-only.ps1 first."
    }
}

$packageName = "MaaCore-sdk-$Target-$Version"
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("maacore-sdk-" + [Guid]::NewGuid().ToString("N"))
$stagingDir = Join-Path $stagingRoot $packageName
$stagingBin = Join-Path $stagingDir "bin"
$stagingInclude = Join-Path $stagingDir "include"
New-Item -ItemType Directory -Path $stagingBin -Force | Out-Null
New-Item -ItemType Directory -Path $stagingInclude -Force | Out-Null

try {
    Write-Host "Staging build outputs"
    Copy-Item -LiteralPath $dllPath -Destination $stagingBin -Force
    Copy-Item -LiteralPath $maautilsPath -Destination $stagingBin -Force
    if (Test-Path $pdbPath) {
        Copy-Item -LiteralPath $pdbPath -Destination $stagingBin -Force
    }
    $maautilsPdb = Join-Path $buildBin "MaaUtils.pdb"
    if (Test-Path $maautilsPdb) {
        Copy-Item -LiteralPath $maautilsPdb -Destination $stagingBin -Force
    }

    $runtimeDir = Join-Path $RepoRoot "deps\runtime\maa-x64-windows"
    if (-not (Test-Path $runtimeDir)) {
        throw "Runtime dependency directory not found: $runtimeDir. Run tools/bootstrap-standalone.ps1 first."
    }

    foreach ($dll in Get-ChildItem -LiteralPath $runtimeDir -File -Filter *.dll) {
        # Prefer artifacts produced by this build over anything stale in the bundle.
        if (($dll.Name -eq 'MaaUtils.dll') -or ($dll.Name -eq 'MaaCore.dll')) {
            continue
        }
        if ((-not $IncludeCuda) -and ($dll.Name -eq 'onnxruntime_providers_cuda.dll')) {
            continue
        }
        Copy-Item -LiteralPath $dll.FullName -Destination $stagingBin -Force
    }

    Write-Host "Staging public headers"
    $publicInclude = Join-Path $RepoRoot "include\upstream"
    if (-not (Test-Path $publicInclude)) {
        throw "Public headers not found: $publicInclude"
    }
    Get-ChildItem -LiteralPath $publicInclude -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $stagingInclude -Force
    }

    $sdkReadme = Join-Path $PSScriptRoot "sdk\README.md"
    if (Test-Path $sdkReadme) {
        Copy-Item -LiteralPath $sdkReadme -Destination (Join-Path $stagingDir "README.md") -Force
    }

    $license = Join-Path $RepoRoot "MaaUtils\LICENSE.md"
    if (Test-Path $license) {
        Copy-Item -LiteralPath $license -Destination (Join-Path $stagingDir "LICENSE.md") -Force
    }

    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    $zipPath = Join-Path $OutputDir "$packageName.zip"
    if (Test-Path $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Write-Host "Compressing to $zipPath"
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stagingDir,
        $zipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true
    )

    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sizeMb = [Math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)

    Write-Host ""
    Write-Host "Created: $zipPath"
    Write-Host "Size:    $sizeMb MB"
    Write-Host "SHA256:  $hash"
}
finally {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}
