#Run selected targets together:
#.\release-all.ps1 -Backend -Web -Phone -Windows
#Or everything:
#.\release-all.ps1 -All

[CmdletBinding()]
param(
    [switch]$Backend,
    [switch]$Web,
    [switch]$Phone,
    [switch]$Windows,
    [switch]$AdminConsole,
    [switch]$All,
    [string]$DeviceId
)

$ErrorActionPreference = 'Stop'

if ($All) {
    $Backend = $true
    $Web = $true
    $Phone = $true
    $Windows = $true
    $AdminConsole = $true
}
if (-not ($Backend -or $Web -or $Phone -or $Windows -or $AdminConsole)) {
    Write-Host 'Select at least one target:'
    Write-Host '  .\release-all.ps1 -Backend -Web -Phone -Windows'
    Write-Host '  .\release-all.ps1 -All -DeviceId PHONE_SERIAL'
    exit 1
}

if ($Backend) {
    & (Join-Path $PSScriptRoot 'deploy-backend.ps1') -AllFunctions
}
if ($Web) {
    & (Join-Path $PSScriptRoot 'deploy-web.ps1')
}
if ($Phone) {
    & (Join-Path $PSScriptRoot 'deploy-phone.ps1') -DeviceId $DeviceId
}
if ($Windows -or $AdminConsole) {
    & (Join-Path $PSScriptRoot 'build-windows.ps1') `
        -MainApp:$Windows -AdminConsole:$AdminConsole
}

Write-Host 'All selected release tasks completed.' -ForegroundColor Green
