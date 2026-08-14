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

# Parsing `adb devices` list output in this host has proven unreliable:
# across many repeated attempts (direct pipe capture, redirect-to-file,
# added delays, a two-read stability check with per-token length
# validation) it kept intermittently truncating the device serial down to
# its first character. Root cause not pinned down. Given that, prefer a
# path that never needs to parse the device list at all:
#   - If the caller passes -DeviceId, skip detection entirely and just
#     confirm that specific device answers (`adb -s ID get-state`), which
#     returns a short, unambiguous single word ("device") rather than a
#     multi-column list to parse.
#   - If -DeviceId is omitted, make ONE best-effort attempt at detection
#     (retrying it further doesn't help - the corruption reproduced on
#     100% of attempts when it happened) and fail fast with a clear
#     pointer to -DeviceId rather than a long, pointless retry loop.
if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
    $state = (& $adb -s $DeviceId get-state 2>&1 | Out-String).Trim()
    if ($state -ne 'device') {
        throw "Device '$DeviceId' is not connected and authorized (adb get-state returned: $state)."
    }
} else {
    $devicesFile = [System.IO.Path]::GetTempFileName()
    try {
        & $adb devices > $devicesFile 2>&1
        Start-Sleep -Milliseconds 500
        $raw = Get-Content -LiteralPath $devicesFile -Raw
    } finally {
        Remove-Item -LiteralPath $devicesFile -Force -ErrorAction SilentlyContinue
    }
    $deviceLines = @(($raw -split "`r`n|`n") | Where-Object { $_ -match '\S+\s+device$' })
    if ($deviceLines.Count -eq 0) {
        throw 'No authorized Android phone found. Connect it and enable USB debugging.'
    }
    if ($deviceLines.Count -gt 1) {
        throw 'Multiple phones found. Run again with -DeviceId SERIAL.'
    }
    if ($deviceLines[0] -notmatch '^(\S+)' -or $Matches[1].Length -lt 6) {
        throw "Could not reliably read the device serial from adb (got: '$($deviceLines[0])'). Re-run with -DeviceId SERIAL instead - run 'adb devices' yourself to find it."
    }
    $DeviceId = $Matches[1]
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
