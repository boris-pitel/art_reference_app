[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$releaseNotesDirectory = Join-Path $repoRoot 'docs\releases'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$pubspec = [System.IO.File]::ReadAllText($pubspecPath)
$match = [regex]::Match(
    $pubspec,
    '(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$'
)
if (-not $match.Success) {
    throw 'Could not find the release version in pubspec.yaml.'
}

$version = $match.Groups[1].Value
$notesPath = Join-Path $releaseNotesDirectory "$version.md"

if (Test-Path $notesPath) {
    Write-Host "Release notes already exist: $notesPath" -ForegroundColor Green
    exit 0
}

[System.IO.Directory]::CreateDirectory($releaseNotesDirectory) | Out-Null
$template = @"
# Painter Reference $version

Released $(Get-Date -Format 'yyyy-MM-dd').

## Features and improvements

- TODO: Describe the user-visible improvements.

## Bugs fixed

- TODO: Describe the resolved issues.

## Deployment

- TODO: Record the deployed targets.
"@
[System.IO.File]::WriteAllText($notesPath, $template, $utf8)
Write-Host "Release-notes template created: $notesPath" -ForegroundColor Green
