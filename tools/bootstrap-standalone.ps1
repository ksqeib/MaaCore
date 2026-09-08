param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$SkipMaaDepsDownload
)

$ErrorActionPreference = "Stop"

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FilePath $($Arguments -join ' ')"
    }
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Host "==> $Name"
    & $Action
}

Invoke-Step "Init MaaUtils submodule" {
    Invoke-External -FilePath "git" -Arguments @("-C", $RepoRoot, "submodule", "update", "--init", "--recursive", "MaaUtils")
}

Invoke-Step "Validate local headers" {
    $requiredPaths = @(
        (Join-Path $RepoRoot "include\upstream\AsstCaller.h"),
        (Join-Path $RepoRoot "include\upstream\AsstCallerExtra.h"),
        (Join-Path $RepoRoot "include\upstream\AsstPort.h"),
        (Join-Path $RepoRoot "include\3rd\calculator\calculator.hpp"),
        (Join-Path $RepoRoot "include\3rd\zlib\decompress.hpp"),
        (Join-Path $RepoRoot "include\3rd\Arknights-Tile-Pos\TileCalc2.hpp")
    )

    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path $requiredPath)) {
            throw "Missing required header: $requiredPath"
        }
    }
}

if (-not $SkipMaaDepsDownload) {
    Invoke-Step "Ensure MaaDeps is ready" {
        $maadepsCmakePath = Join-Path $RepoRoot "MaaUtils\MaaDeps\maadeps.cmake"
        $tripletPath = Join-Path $RepoRoot "MaaUtils\MaaDeps\vcpkg\installed\maa-x64-windows"

        if ((-not (Test-Path $maadepsCmakePath)) -or (-not (Test-Path $tripletPath))) {
            Invoke-External -FilePath "python" -Arguments @((Join-Path $RepoRoot "tools\maadeps-download.py"))
        }
        else {
            Write-Host "MaaDeps already exists at $tripletPath"
        }

        if (-not (Test-Path $maadepsCmakePath)) {
            throw "MaaDeps bootstrap finished but maadeps.cmake was not found: $maadepsCmakePath"
        }

        if (-not (Test-Path $tripletPath)) {
            throw "MaaDeps bootstrap finished but installed triplet was not found: $tripletPath"
        }
    }
}

Write-Host ""
Write-Host "Standalone prerequisites are ready."
Write-Host "Build with:"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\tools\build-maacore-only.ps1 -SkipBootstrap -UseSccache -NoFresh"

