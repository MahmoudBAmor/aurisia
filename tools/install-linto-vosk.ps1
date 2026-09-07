[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$packDirectory = Join-Path $projectRoot "models\linto-asr-ar-tn-android-v0.1"
$modelDirectory = Join-Path $packDirectory "android-model"
$revision = "8ad50ec266ecfba2aec33579b4434384c97eb49a"
$archiveUri = "https://huggingface.co/linagora/linto-asr-ar-tn-0.1/resolve/$revision/android-model.zip"
$archiveSha256 = "91811df61515172420c583bb901cd6c4c200a6e4fdf3437f539f5dcf851cbd29"
$archiveSize = 165666389
$modelSize = 278892054

$criticalArtifacts = @(
    @{
        Path = "am\final.mdl"
        Sha256 = "9462fea3133f2b3ef672df2cabffb749f5eedf49427bff7bedd3457a9dfd7da3"
        Size = 77422160
    },
    @{
        Path = "am\tree"
        Sha256 = "841160139eae5a74a5ebb69fa407ff8db25d2e57d7344e929f246ea05b9dfc6c"
        Size = 658228
    },
    @{
        Path = "graph\Gr.fst"
        Sha256 = "7d492f26dadb789bcf9d5f9cf01117f4317fbbd69ba2bab1b9510a25fb050955"
        Size = 113640399
    },
    @{
        Path = "graph\HCLr.fst"
        Sha256 = "915ff522cd79cea91dd3cdbac05529672c553cfef50d6a5bb9d6a6f3104ce1ce"
        Size = 35141746
    },
    @{
        Path = "graph\words.txt"
        Sha256 = "4a81aa2cf423b002bfb87617dfcaf8f7c2f154e8b688ba071648d9012661980f"
        Size = 5579403
    },
    @{
        Path = "ivector\final.ie"
        Sha256 = "0b56ff4f9f0584989a87542f03b8890e65304cb596d167fb03a94af87215b0de"
        Size = 19757687
    },
    @{
        Path = "conf\model.conf"
        Sha256 = "32339b4154371a2a6d2fa7a87320316e6b145375a9bd26917214a67b56987380"
        Size = 277
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

function Test-ModelDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }
    $actualSize = (
        Get-ChildItem -LiteralPath $Path -File -Recurse |
            Measure-Object -Property Length -Sum
    ).Sum
    if ($actualSize -ne $modelSize) {
        return $false
    }
    foreach ($artifact in $criticalArtifacts) {
        if (-not (Test-VerifiedFile `
            -Path (Join-Path $Path $artifact.Path) `
            -Sha256 $artifact.Sha256 `
            -Size $artifact.Size
        )) {
            return $false
        }
    }
    return $true
}

if (Test-ModelDirectory -Path $modelDirectory) {
    Write-Host "LinTO Tunisian Android model is already installed and verified."
    exit 0
}
if (Test-Path -LiteralPath $modelDirectory) {
    throw "An incomplete LinTO model directory already exists: $modelDirectory"
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "aurisia-linto-$PID"
New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $packDirectory -Force | Out-Null

try {
    $archivePath = Join-Path $temporaryDirectory "android-model.zip"
    Invoke-WebRequest -Uri $archiveUri -OutFile $archivePath
    if (-not (Test-VerifiedFile `
        -Path $archivePath `
        -Sha256 $archiveSha256 `
        -Size $archiveSize
    )) {
        throw "Downloaded LinTO archive failed size or SHA-256 verification."
    }

    $expandedRoot = Join-Path $temporaryDirectory "expanded"
    Expand-Archive -LiteralPath $archivePath -DestinationPath $expandedRoot
    $expandedModel = Join-Path $expandedRoot "android-model"
    if (-not (Test-ModelDirectory -Path $expandedModel)) {
        throw "Extracted LinTO model failed artifact verification."
    }
    Move-Item -LiteralPath $expandedModel -Destination $modelDirectory
}
finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-ModelDirectory -Path $modelDirectory)) {
    throw "Installed LinTO model failed verification."
}

Write-Host "LinTO Tunisian Android model is installed and verified."
