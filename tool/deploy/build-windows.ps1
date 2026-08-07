[CmdletBinding()]
param(
    [switch]$MainApp,
    [switch]$AdminConsole
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found on PATH.'
}
if (-not $MainApp -and -not $AdminConsole) {
    $MainApp = $true
}

if ($MainApp) {
    Set-Location $repoRoot
    Write-Host 'Building the main Windows application...'
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Main Windows build failed.' }
    Write-Host "Main release: $repoRoot\build\windows\x64\runner\Release"
}

if ($AdminConsole) {
    Set-Location (Join-Path $repoRoot 'admin_console')
    Write-Host 'Building the Windows admin console...'
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Admin console build failed.' }
    Write-Host "Admin release: $repoRoot\admin_console\build\windows\x64\runner\Release"
}

Write-Host 'Windows build completed.' -ForegroundColor Green
