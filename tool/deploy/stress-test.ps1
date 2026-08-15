[CmdletBinding()]
param(
    [string]$Device = 'windows'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter was not found on PATH.'
}

Write-Host 'Running the upload/download stress benchmark against the live backend...'
& flutter test integration_test/upload_download_stress_test.dart -d $Device
if ($LASTEXITCODE -ne 0) { throw 'Upload/download stress benchmark failed.' }

Write-Host 'Stress benchmark completed. See console output above for timing stats.' -ForegroundColor Green
