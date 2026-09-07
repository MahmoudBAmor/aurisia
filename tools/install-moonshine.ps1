[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$modelName = "sherpa-onnx-moonshine-base-ar-quantized-2026-02-27"
$modelDirectory = Join-Path $projectRoot "models\$modelName"
$archiveUri = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$modelName.tar.bz2"
$archiveSha256 = "4d3f16fe354d8536d3323d3eaf4c12fafb1976b5dc0a12862ab25934da94285b"
$archiveSize = 119143068

$artifacts = @(
    @{
        Name = "encoder_model.ort"
        Sha256 = "68e50ebe0317ce909f098044a5dda2a76e6b86dc882829a317771fbafc5826ae"
        Size = 31326824
    },
    @{
        Name = "decoder_model_merged.ort"
        Sha256 = "8f272cb50818e28ad86bbffc21e1450a4d57155e95f099ca6a236f38f4d9eafb"
        Size = 109424552
    },
    @{
        Name = "tokens.txt"
        Sha256 = "2870d843e14c1e187bf1913a521562a63b53933814bd7f2145120468f494a049"
        Size = 549350
    },
    @{
        Name = "LICENSE"
        Sha256 = "6148d7574a6554b7379b633cfd4c4fe5840c3f548d13bc83e00b52dc6fa00abd"
        Size = 13344
    }
)

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

function Test-InstalledPack {
    foreach ($artifact in $artifacts) {
        $path = Join-Path $modelDirectory $artifact.Name
        if (-not (Test-VerifiedFile `
            -Path $path `
            -Sha256 $artifact.Sha256 `
            -Size $artifact.Size
        )) {
            return $false
        }
    }
    return $true
}

if (Test-InstalledPack) {
    Write-Host "Moonshine Arabic evaluation model is already installed and verified."
    exit 0
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "aurisia-moonshine-$PID"
New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $modelDirectory -Force | Out-Null

try {
    $archivePath = Join-Path $temporaryDirectory "$modelName.tar.bz2"
    Invoke-WebRequest -Uri $archiveUri -OutFile $archivePath
    if (-not (Test-VerifiedFile `
        -Path $archivePath `
        -Sha256 $archiveSha256 `
        -Size $archiveSize
    )) {
        throw "Downloaded Moonshine archive failed size or SHA-256 verification."
    }

    & tar.exe -xf $archivePath -C $temporaryDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "Windows tar failed to extract the Moonshine archive."
    }
    $expandedDirectory = Join-Path $temporaryDirectory $modelName
    foreach ($artifact in $artifacts) {
        $source = Join-Path $expandedDirectory $artifact.Name
        if (-not (Test-VerifiedFile `
            -Path $source `
            -Sha256 $artifact.Sha256 `
            -Size $artifact.Size
        )) {
            throw "Extracted Moonshine artifact failed verification: $($artifact.Name)"
        }
        Copy-Item `
            -LiteralPath $source `
            -Destination (Join-Path $modelDirectory $artifact.Name) `
            -Force
    }
}
finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-InstalledPack)) {
    throw "Installed Moonshine model pack failed verification."
}

Write-Host "Moonshine Arabic evaluation model is installed and verified."
