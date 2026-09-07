[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeDirectory = Join-Path $projectRoot "runtimes\whisper.cpp-v1.8.5"
$modelDirectory = Join-Path $projectRoot "models\whisper-small-q5_1"
$modelPath = Join-Path $modelDirectory "ggml-small-q5_1.bin"

$runtimeUri = "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.5/whisper-bin-x64.zip"
$runtimeSha256 = "2a0e85915d0ff9e2a1d1b45b19973f05fbcdfb51d3af03557454acf6ccaa5e8a"
$runtimeSize = 4092743
$modelUri = "https://huggingface.co/ggerganov/whisper.cpp/resolve/c521a4b02f422512d734391fdf08bb08c0862f68/ggml-small-q5_1.bin?download=true"
$modelSha256 = "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
$modelSize = 190085487

function Test-VerifiedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [Parameter(Mandatory = $true)][long]$Size
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -ne $Size) {
        return $false
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Sha256
}

function Get-VerifiedDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [Parameter(Mandatory = $true)][long]$Size
    )

    Invoke-WebRequest -Uri $Uri -OutFile $Destination
    if (-not (Test-VerifiedFile -Path $Destination -Sha256 $Sha256 -Size $Size)) {
        throw "Downloaded artifact failed size or SHA-256 verification: $Uri"
    }
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "aurisia-whisper-$PID"
New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $modelDirectory -Force | Out-Null

try {
    $runtimeArchive = Join-Path $temporaryDirectory "whisper-bin-x64.zip"
    Get-VerifiedDownload `
        -Uri $runtimeUri `
        -Destination $runtimeArchive `
        -Sha256 $runtimeSha256 `
        -Size $runtimeSize

    $expandedRuntime = Join-Path $temporaryDirectory "runtime"
    Expand-Archive -LiteralPath $runtimeArchive -DestinationPath $expandedRuntime
    $releaseDirectory = Join-Path $expandedRuntime "Release"
    foreach ($name in @(
        "whisper-cli.exe",
        "whisper-server.exe",
        "whisper.dll",
        "ggml-base.dll",
        "ggml-cpu.dll",
        "ggml.dll"
    )) {
        Copy-Item `
            -LiteralPath (Join-Path $releaseDirectory $name) `
            -Destination (Join-Path $runtimeDirectory $name) `
            -Force
    }

    if (-not (Test-VerifiedFile -Path $modelPath -Sha256 $modelSha256 -Size $modelSize)) {
        $temporaryModel = Join-Path $temporaryDirectory "ggml-small-q5_1.bin"
        Get-VerifiedDownload `
            -Uri $modelUri `
            -Destination $temporaryModel `
            -Sha256 $modelSha256 `
            -Size $modelSize
        Copy-Item -LiteralPath $temporaryModel -Destination $modelPath -Force
    }
}
finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

$runtimeExecutable = Join-Path $runtimeDirectory "whisper-server.exe"
$runtimeExecutableSha256 = "3940709f1d3df485af0c7f2972ed82ca617df0386c63fcd87199902365083407"
if (-not (Test-VerifiedFile `
    -Path $runtimeExecutable `
    -Sha256 $runtimeExecutableSha256 `
    -Size 727552
)) {
    throw "Installed whisper.cpp server executable failed verification."
}

Write-Host "whisper.cpp 1.8.5 and Whisper small-q5_1 are installed and verified."
