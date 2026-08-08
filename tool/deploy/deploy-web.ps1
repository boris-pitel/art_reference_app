[CmdletBinding()]
param(
    [switch]$BuildOnly,
    [switch]$SkipVersionBump
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

if (-not $SkipVersionBump) {
    & (Join-Path $PSScriptRoot 'increment-version.ps1')
}

foreach ($command in @('flutter', 'firebase')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "$command was not found on PATH."
    }
}

Write-Host 'Building the production web application...'
& flutter build web --release
if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }

if ($BuildOnly) {
    Write-Host "Web build created at $repoRoot\build\web" -ForegroundColor Green
    exit 0
}

Write-Host 'Deploying web build to Firebase Hosting...'
& firebase deploy --only hosting
if ($LASTEXITCODE -ne 0) { throw 'Firebase Hosting deployment failed.' }

Write-Host 'Web deployment completed.' -ForegroundColor Green
