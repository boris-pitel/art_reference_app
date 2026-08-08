[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$versionPath = Join-Path $repoRoot 'lib\app_version.dart'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$pubspec = [System.IO.File]::ReadAllText($pubspecPath)
$match = [regex]::Match(
    $pubspec,
    '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
)
if (-not $match.Success) {
    throw 'Could not find a semantic version with a build number in pubspec.yaml.'
}

$publicVersion = $match.Groups[1].Value
$buildNumber = [int]$match.Groups[2].Value + 1
$newVersion = "$publicVersion+$buildNumber"
$updatedPubspec = $pubspec.Remove($match.Index, $match.Length).Insert(
    $match.Index,
    "version: $newVersion"
)
[System.IO.File]::WriteAllText($pubspecPath, $updatedPubspec, $utf8)

$versionSource = [System.IO.File]::ReadAllText($versionPath)
$updatedVersionSource = [regex]::Replace(
    $versionSource,
    "const String appVersion = '[^']+';",
    "const String appVersion = '$newVersion';"
)
if ($updatedVersionSource -eq $versionSource) {
    throw 'Could not update lib\app_version.dart.'
}
[System.IO.File]::WriteAllText($versionPath, $updatedVersionSource, $utf8)

Write-Host "Release version increased to $newVersion." -ForegroundColor Green
