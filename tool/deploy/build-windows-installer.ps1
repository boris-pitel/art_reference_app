[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(?<version>\d+\.\d+\.\d+)\+(?<build>\d+)\s*$')

if (-not $versionMatch.Success) {
    throw "Could not read a semantic version and build number from $pubspecPath"
}

$appVersion = $versionMatch.Groups['version'].Value
$buildNumber = $versionMatch.Groups['build'].Value
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$appExecutable = Join-Path $releaseDir 'art_reference_app.exe'
$installerScript = Join-Path $projectRoot 'installer\painter-reference.iss'
$outputPath = Join-Path $projectRoot "dist\PainterReference-Setup-$appVersion-$buildNumber.exe"

if (-not $SkipBuild) {
    Push-Location $projectRoot
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter Windows build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $appExecutable)) {
    throw "Windows release executable was not found at $appExecutable"
}

$runtimeDlls = @(
    'msvcp140.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll'
)

foreach ($dll in $runtimeDlls) {
    $source = Join-Path $env:SystemRoot "System32\$dll"
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required Visual C++ runtime file was not found at $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $releaseDir $dll) -Force
}

$programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$isccCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
    (Join-Path $programFilesX86 'Inno Setup 7\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path $programFilesX86 'Inno Setup 6\ISCC.exe')
)
$iscc = $isccCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

if (-not $iscc) {
    throw 'Inno Setup Compiler (ISCC.exe) was not found. Install Inno Setup 6 or 7 and retry.'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue

& $iscc "/DAppVersion=$appVersion" "/DBuildNumber=$buildNumber" $installerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $outputPath)) {
    throw "Installer was not produced at $outputPath"
}

$installer = Get-Item -LiteralPath $outputPath
$hash = Get-FileHash -LiteralPath $outputPath -Algorithm SHA256
$signature = Get-AuthenticodeSignature -LiteralPath $outputPath

[pscustomobject]@{
    Installer = $installer.FullName
    Version = "$appVersion+$buildNumber"
    SizeBytes = $installer.Length
    SHA256 = $hash.Hash
    SignatureStatus = $signature.Status
}
