#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads and verifies the pinned Android build toolchain (SHA-256 locked).
#>
param(
    [string]$CacheDirectory = ''
)

$ErrorActionPreference = 'Stop'
$runningOnWindows = ($PSVersionTable.PSVersion.Major -le 5) -or ($IsWindows -eq $true) -or ($env:OS -eq 'Windows_NT')
if (-not $runningOnWindows) {
    throw 'This pinned toolchain is Windows-only. See docs/BUILD.md.'
}

$toolsDir = Join-Path $PSScriptRoot 'tools'
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tools.lock.json') -Raw | ConvertFrom-Json
foreach ($item in $lock) {
    $path = Join-Path $toolsDir $item.file
    if (-not (Test-Path -LiteralPath $path)) {
        $cached = if ($CacheDirectory) { Join-Path $CacheDirectory $item.file } else { '' }
        if ($cached -and (Test-Path -LiteralPath $cached)) {
            Write-Host "Copying cached $($item.file)"
            Copy-Item -LiteralPath $cached -Destination $path
        } else {
            Write-Host "Downloading $($item.file)"
            Invoke-WebRequest -Uri $item.url -OutFile $path
        }
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $item.sha256) {
        throw "Checksum mismatch for $($item.file): expected $($item.sha256), got $actual"
    }

    if ($item.extract) {
        $probePath = Join-Path $toolsDir $item.probe
        if (-not (Test-Path -LiteralPath $probePath)) {
            Write-Host "Extracting $($item.file)"
            Expand-Archive -LiteralPath $path -DestinationPath (Join-Path $toolsDir $item.extract) -Force
        }
    }

    Write-Host "Verified $($item.file)"
}

Write-Host 'Toolchain ready. Next: .\build.ps1'
