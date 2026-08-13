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

# Piping `adb devices` straight through the PowerShell pipeline is
# unreliable in this host: capturing via `| Where-Object { ... }` on the
# direct pipe output, or reading a redirected-to-file copy immediately, can
# both intermittently return truncated text (reproduced repeatedly - looked
# like a native-command stdout interop race, confirmed by the fact that a
# short delay before reading the redirected file consistently fixed it).
# Retry with a brief delay until the parsed output actually looks complete,
# instead of trusting the first read.
$deviceLines = @()
for ($attempt = 1; $attempt -le 5; $attempt++) {
    $devicesFile = [System.IO.Path]::GetTempFileName()
    try {
        & $adb devices > $devicesFile 2>&1
        Start-Sleep -Milliseconds 400
        $rawDevices = Get-Content -LiteralPath $devicesFile -Raw
    } finally {
        Remove-Item -LiteralPath $devicesFile -Force -ErrorAction SilentlyContinue
    }
    $candidateLines = ($rawDevices -split "`r`n|`n") | Where-Object {
        $_ -match '\S+\s+device$'
    }
    # A real serial is much longer than a single character; anything
    # shorter means this read caught a still-flushing file.
    $looksComplete = ($candidateLines.Count -gt 0) -and (
        $candidateLines | Where-Object { $_.Length -lt 6 }
    ).Count -eq 0
    if ($looksComplete) {
        $deviceLines = $candidateLines
        break
    }
    Start-Sleep -Milliseconds (300 * $attempt)
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
