<#
.SYNOPSIS
    Package the local deps/ tree into a publishable dependency bundle.

.DESCRIPTION
    Creates a zip whose top-level directory is `deps/`, so it can be extracted at the
    repository root by tools/fetch-deps.ps1. The CUDA execution provider is omitted by
    default because it is ~170 MB and not required by typical launchers (DirectML is
    kept for GPU inference).

    After uploading the zip to a GitHub release, run again with -UpdateManifest so
    tools/deps-manifest.json points at the new asset and hash.

.EXAMPLE
    powershell -File .\tools\pack-deps.ps1 -UpdateManifest
#>
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$DepsDir = "",
    [string]$OutputDir = "",
    [string]$BundleVersion = "v3",
    [string]$Target = "windows-x64",
    [string]$RepoSlug = "",
    [switch]$IncludeCuda,
    [switch]$UpdateManifest
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($DepsDir)) {
    $DepsDir = Join-Path $RepoRoot "deps"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RepoRoot "dist"
}
$manifestPath = Join-Path $PSScriptRoot "deps-manifest.json"

if (-not (Test-Path $DepsDir)) {
    throw "Deps directory not found: $DepsDir"
}

if ([string]::IsNullOrWhiteSpace($RepoSlug)) {
    $remote = git -C $RepoRoot remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) {
        throw "Could not determine repository slug. Pass -RepoSlug owner/repo."
    }
    $RepoSlug = $remote.Trim()
    if ($RepoSlug -match 'github\.com[:/](?<slug>[^/]+/[^/]+?)(\.git)?$') {
        $RepoSlug = $Matches['slug']
    }
    else {
        throw "Origin is not a GitHub remote: $remote. Pass -RepoSlug owner/repo."
    }
}

$assetName = "MaaCore-deps-$Target-$BundleVersion.zip"
$zipPath = Join-Path $OutputDir $assetName
$releaseTag = "deps-$BundleVersion"
$assetUrl = "https://github.com/$RepoSlug/releases/download/$releaseTag/$assetName"

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("maacore-deps-" + [Guid]::NewGuid().ToString("N"))
$stagingDeps = Join-Path $stagingRoot "deps"
New-Item -ItemType Directory -Path $stagingDeps -Force | Out-Null

try {
    Write-Host "Staging $DepsDir"
    $excludePatterns = @('\.bundle-version$', 'runtime/.*MaaUtils\.dll$')
    if (-not $IncludeCuda) {
        $excludePatterns += 'onnxruntime_providers_cuda\.dll$'
    }

    Get-ChildItem -LiteralPath $DepsDir -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($DepsDir.Length).TrimStart('\', '/')
        $matchPath = $relative -replace '\\', '/'
        foreach ($pattern in $excludePatterns) {
            if ($matchPath -match $pattern) {
                return
            }
        }
        $destination = Join-Path $stagingDeps $relative
        $destinationDir = Split-Path -Parent $destination
        if (-not (Test-Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }

    if (Test-Path $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Write-Host "Compressing to $zipPath"
    $fixedTimestamp = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem -LiteralPath $stagingDeps -Recurse -File | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($stagingDeps.Length).TrimStart('\', '/') -replace '\\', '/'
            $entry = $zip.CreateEntry("deps/$relative", [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $fixedTimestamp
            $fileStream = [System.IO.File]::OpenRead($_.FullName)
            try {
                $entryStream = $entry.Open()
                try {
                    $fileStream.CopyTo($entryStream)
                }
                finally {
                    $entryStream.Dispose()
                }
            }
            finally {
                $fileStream.Dispose()
            }
        }
    }
    finally {
        $zip.Dispose()
    }
}
finally {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sizeMb = [Math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)

Write-Host ""
Write-Host "Created: $zipPath"
Write-Host "Size:    $sizeMb MB"
Write-Host "SHA256:  $hash"
Write-Host "URL:     $assetUrl"

if ($UpdateManifest) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    $targets = [ordered]@{}
    foreach ($property in $manifest.targets.PSObject.Properties) {
        $targets[$property.Name] = [ordered]@{
            url    = [string]$property.Value.url
            sha256 = [string]$property.Value.sha256
        }
    }
    $targets[$Target] = [ordered]@{
        url    = $assetUrl
        sha256 = $hash
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('{')
    $lines.Add('  "schemaVersion": 1,')
    $lines.Add("  `"bundleVersion`": `"$BundleVersion`",")
    $lines.Add('  "targets": {')
    $names = @($targets.Keys)
    for ($i = 0; $i -lt $names.Count; $i++) {
        $name = $names[$i]
        $entry = $targets[$name]
        $lines.Add("    `"$name`": {")
        $lines.Add("      `"url`": `"$($entry.url)`",")
        $lines.Add("      `"sha256`": `"$($entry.sha256)`"")
        $comma = ""
        if ($i -lt ($names.Count - 1)) {
            $comma = ","
        }
        $lines.Add("    }$comma")
    }
    $lines.Add('  }')
    $lines.Add('}')

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($manifestPath, ($lines -join "`n"), $utf8NoBom)
    Write-Host "Updated $manifestPath"
}

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Create a GitHub release tagged '$releaseTag' (or use an existing one)."
Write-Host "  2. Upload '$assetName' as a release asset."
Write-Host "  3. Commit the updated tools/deps-manifest.json."
Write-Host ""
Write-Host "  gh release create $releaseTag `"$zipPath`" --title `"MaaCore deps $BundleVersion`" --notes `"Prebuilt MaaCore dependencies ($Target)`""
