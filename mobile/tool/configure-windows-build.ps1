[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $env:LOCALAPPDATA "Aurisia\flutter-build")
)

$ErrorActionPreference = "Stop"

$mobileRoot = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $mobileRoot "build"
$destinationPath = [System.IO.Path]::GetFullPath($Destination)

if (-not $env:LOCALAPPDATA) {
    throw "LOCALAPPDATA is not defined. Pass -Destination with a local, non-OneDrive path."
}

New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null

if (Test-Path -LiteralPath $buildPath) {
    $buildItem = Get-Item -LiteralPath $buildPath -Force
    if ($buildItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $currentTarget = @($buildItem.Target)[0]
        if ($currentTarget -and
            [System.IO.Path]::GetFullPath($currentTarget) -eq $destinationPath) {
            Write-Host "Aurisia build directory is already local: $destinationPath"
            exit 0
        }
    }

    Write-Host "Removing generated Flutter build output from: $buildPath"
    Remove-Item -LiteralPath $buildPath -Recurse -Force
}

New-Item -ItemType Junction -Path $buildPath -Target $destinationPath | Out-Null
Write-Host "Aurisia build directory now points to: $destinationPath"
