[CmdletBinding()]
param(
    [string]$DeviceId,
    [switch]$SkipVersionBump
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

if (-not $SkipVersionBump) {
    & (Join-Path $PSScriptRoot 'increment-version.ps1')
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found on PATH.'
}

$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($null -eq $adbCommand) {
    $sdkAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path $sdkAdb) {
        $adb = $sdkAdb
    } else {
        throw 'ADB was not found. Install Android SDK Platform Tools.'
    }
} else {
    $adb = $adbCommand.Source
}

$deviceLines = @(& $adb devices) | Select-Object -Skip 1 | Where-Object {
    $_ -match '\S+\s+device$'
}
if ($deviceLines.Count -eq 0) {
    throw 'No authorized Android phone found. Connect it and enable USB debugging.'
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    if ($deviceLines.Count -gt 1) {
        throw 'Multiple phones found. Run again with -DeviceId SERIAL.'
    }
    if ($deviceLines[0] -notmatch '^(\S+)') {
        throw "Could not parse a device serial from: $($deviceLines[0])"
    }
    $DeviceId = $Matches[1]
} elseif (-not ($deviceLines | Where-Object {
    $_ -match '^(\S+)' -and $Matches[1] -eq $DeviceId
})) {
    throw "Device '$DeviceId' is not connected and authorized."
}

Write-Host "Building release APK for device $DeviceId..."
& flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' }

$apk = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apk)) { throw "Release APK was not created at $apk" }

Write-Host 'Installing the APK without clearing existing app data...'
& $adb -s $DeviceId install -r $apk
if ($LASTEXITCODE -ne 0) { throw 'APK installation failed.' }

Write-Host "Installed successfully on $DeviceId." -ForegroundColor Green
