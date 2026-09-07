[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$voskDestination = Join-Path $projectRoot "mobile\assets\model_packs\aeb-TN-vosk-full"
$formalArabicDestination = Join-Path $projectRoot "mobile\assets\model_packs\ar-MGB2-vosk"
$qwenDestination = Join-Path $projectRoot "mobile\assets\model_packs\qwen3-asr-0.6B-int8"
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "aurisia-mobile-models-$PID"

$artifacts = @(
    @{
        Name = "STT_Tun_Model.zip"
        Uri = "https://huggingface.co/Sali7a8603/Tunisian_STT/resolve/4ff4f5c84d7cc3065818202b6194b3c52084663d/STT_Tun_Model.zip"
        Sha256 = "64e999b1bc27237e714ff6650fc7bd86d5ce10eb8d410c3495f46496da5d577d"
        Size = 541801652
        Destination = $voskDestination
        LocalSource = Join-Path $voskDestination "STT_Tun_Model.zip"
    },
    @{
        Name = "silero_vad.onnx"
        Uri = "https://raw.githubusercontent.com/snakers4/silero-vad/v6.2.1/src/silero_vad/data/silero_vad.onnx"
        Sha256 = "1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3"
        Size = 2327524
        Destination = $voskDestination
        LocalSource = Join-Path $projectRoot "models\silero-vad-v6.2.1\silero_vad.onnx"
    },
    @{
        Name = "speaker_embedding.onnx"
        Uri = "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx"
        Sha256 = "1a331345f04805badbb495c775a6ddffcdd1a732567d5ec8b3d5749e3c7a5e4b"
        Size = 39593761
        Destination = $voskDestination
        LocalSource = Join-Path $projectRoot "models\3dspeaker-eres2net-base-16k\model.onnx"
    },
    @{
        Name = "android-model.zip"
        Uri = "https://alphacephei.com/vosk/models/vosk-model-ar-mgb2-0.4.zip"
        Sha256 = "357469ae1bb4d7a3810c9cd6b86d33bc135898dfc134e6df8bc2ddd28c5fe77a"
        Size = 333241610
        Destination = $formalArabicDestination
        LocalSource = Join-Path $projectRoot "mobile\assets\model_packs\ar-MGB2-vosk\android-model.zip"
    },
    @{
        Name = "silero_vad.onnx"
        Uri = "https://raw.githubusercontent.com/snakers4/silero-vad/v6.2.1/src/silero_vad/data/silero_vad.onnx"
        Sha256 = "1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3"
        Size = 2327524
        Destination = $formalArabicDestination
        LocalSource = Join-Path $projectRoot "models\silero-vad-v6.2.1\silero_vad.onnx"
    },
    @{
        Name = "speaker_embedding.onnx"
        Uri = "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx"
        Sha256 = "1a331345f04805badbb495c775a6ddffcdd1a732567d5ec8b3d5749e3c7a5e4b"
        Size = 39593761
        Destination = $formalArabicDestination
        LocalSource = Join-Path $projectRoot "models\3dspeaker-eres2net-base-16k\model.onnx"
    }
)

$qwenArchive = @{
    Name = "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2"
    Uri = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2"
    Sha256 = "393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96"
    Size = 878702423
    Root = "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25"
}

$qwenFiles = @(
    @{
        RelativePath = "conv_frontend.onnx"
        Sha256 = "d22dc4423e0940e49884e903d2ea2f7e5567c14fc1aed97e4e26d6b8f208ef9e"
        Size = 44148281
    },
    @{
        RelativePath = "encoder.int8.onnx"
        Sha256 = "60748d3e6744a57c9c91e1b17424a6c2990567e8adceb0783940c03ed98fa9d9"
        Size = 182491662
    },
    @{
        RelativePath = "decoder.int8.onnx"
        Sha256 = "4f6885be5959ae26af3089d38ee7972c5fafbeeb1cf8d5e76eab6d8b61ca5771"
        Size = 755914231
    },
    @{
        RelativePath = "tokenizer\merges.txt"
        Sha256 = "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
        Size = 1671853
    },
    @{
        RelativePath = "tokenizer\tokenizer_config.json"
        Sha256 = "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"
        Size = 12487
    },
    @{
        RelativePath = "tokenizer\vocab.json"
        Sha256 = "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
        Size = 2776833
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
    if ((Get-Item -LiteralPath $Path).Length -ne $Size) {
        return $false
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Sha256
}

New-Item -ItemType Directory -Path $voskDestination -Force | Out-Null
New-Item -ItemType Directory -Path $formalArabicDestination -Force | Out-Null
New-Item -ItemType Directory -Path $qwenDestination -Force | Out-Null
New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null

try {
    foreach ($artifact in $artifacts) {
        $target = Join-Path $artifact.Destination $artifact.Name
        if (Test-VerifiedFile -Path $target -Sha256 $artifact.Sha256 -Size $artifact.Size) {
            Write-Host "Already installed and verified: $($artifact.Name)"
            continue
        }
        if (Test-Path -LiteralPath $target) {
            throw "An invalid mobile model artifact already exists: $target"
        }

        if (Test-VerifiedFile `
            -Path $artifact.LocalSource `
            -Sha256 $artifact.Sha256 `
            -Size $artifact.Size
        ) {
            try {
                New-Item -ItemType HardLink -Path $target -Target $artifact.LocalSource | Out-Null
            }
            catch {
                Copy-Item -LiteralPath $artifact.LocalSource -Destination $target
            }
        }
        else {
            $downloadName = "$(Split-Path -Leaf $artifact.Destination)-$($artifact.Name)"
            $download = Join-Path $temporaryDirectory $downloadName
            Invoke-WebRequest -Uri $artifact.Uri -OutFile $download
            if (-not (Test-VerifiedFile `
                -Path $download `
                -Sha256 $artifact.Sha256 `
                -Size $artifact.Size
            )) {
                throw "Downloaded artifact failed verification: $($artifact.Uri)"
            }
            Move-Item -LiteralPath $download -Destination $target
        }

        if (-not (Test-VerifiedFile `
            -Path $target `
            -Sha256 $artifact.Sha256 `
            -Size $artifact.Size
        )) {
            throw "Installed artifact failed verification: $target"
        }
        Write-Host "Installed and verified: $($artifact.Name)"
    }

    $qwenReady = $true
    foreach ($file in $qwenFiles) {
        $target = Join-Path $qwenDestination $file.RelativePath
        if (-not (Test-VerifiedFile -Path $target -Sha256 $file.Sha256 -Size $file.Size)) {
            if (Test-Path -LiteralPath $target) {
                throw "An invalid Qwen3 model artifact already exists: $target"
            }
            $qwenReady = $false
        }
    }

    if (-not $qwenReady) {
        $download = Join-Path $temporaryDirectory $qwenArchive.Name
        Invoke-WebRequest -Uri $qwenArchive.Uri -OutFile $download
        if (-not (Test-VerifiedFile `
            -Path $download `
            -Sha256 $qwenArchive.Sha256 `
            -Size $qwenArchive.Size
        )) {
            throw "Downloaded Qwen3 archive failed verification: $($qwenArchive.Uri)"
        }

        $extraction = Join-Path $temporaryDirectory "qwen3-extracted"
        New-Item -ItemType Directory -Path $extraction -Force | Out-Null
        & tar.exe -xjf $download -C $extraction
        if ($LASTEXITCODE -ne 0) {
            throw "Could not extract the verified Qwen3 archive."
        }
        $sourceRoot = Join-Path $extraction $qwenArchive.Root

        foreach ($file in $qwenFiles) {
            $source = Join-Path $sourceRoot $file.RelativePath
            if (-not (Test-VerifiedFile -Path $source -Sha256 $file.Sha256 -Size $file.Size)) {
                throw "Extracted Qwen3 artifact failed verification: $($file.RelativePath)"
            }
            $target = Join-Path $qwenDestination $file.RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target
            if (-not (Test-VerifiedFile -Path $target -Sha256 $file.Sha256 -Size $file.Size)) {
                throw "Installed Qwen3 artifact failed verification: $target"
            }
            Write-Host "Installed and verified: $($file.RelativePath)"
        }
    }
    else {
        Write-Host "Qwen3-ASR model is already installed and verified."
    }
}
finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Mobile offline model packs are ready in:"
Write-Host "  $voskDestination"
Write-Host "  $formalArabicDestination"
Write-Host "  $qwenDestination"
