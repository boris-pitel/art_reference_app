#Run selected targets together:
#.\release-all.ps1 -Backend -Web -Phone -Windows
#Or everything:
#.\release-all.ps1 -All
#StressTest is optional and not included in -All (it's a slow benchmark,
#not a release gate) - opt in explicitly:
#.\release-all.ps1 -All -StressTest

[CmdletBinding()]
param(
    [switch]$Backend,
    [switch]$Web,
    [switch]$Phone,
    [switch]$Windows,
    [switch]$AdminConsole,
    [switch]$All,
    [switch]$StressTest,
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
if (-not ($Backend -or $Web -or $Phone -or $Windows -or $AdminConsole -or $StressTest)) {
    Write-Host 'Select at least one target:'
    Write-Host '  .\release-all.ps1 -Backend -Web -Phone -Windows'
    Write-Host '  .\release-all.ps1 -All -DeviceId PHONE_SERIAL'
    Write-Host '  .\release-all.ps1 -All -StressTest'
    exit 1
}

if ($Web -or $Phone -or $Windows) {
    & (Join-Path $PSScriptRoot 'increment-version.ps1')
    & (Join-Path $PSScriptRoot 'ensure-release-notes.ps1')
}

if ($Backend) {
    & (Join-Path $PSScriptRoot 'deploy-backend.ps1') -AllFunctions
}
if ($Web) {
    & (Join-Path $PSScriptRoot 'deploy-web.ps1') -SkipVersionBump
}
if ($Phone) {
    & (Join-Path $PSScriptRoot 'deploy-phone.ps1') `
        -DeviceId $DeviceId -SkipVersionBump
}
if ($Windows -or $AdminConsole) {
    & (Join-Path $PSScriptRoot 'build-windows.ps1') `
        -MainApp:$Windows -AdminConsole:$AdminConsole -SkipVersionBump
}
if ($StressTest) {
    & (Join-Path $PSScriptRoot 'stress-test.ps1')
}

Write-Host 'All selected release tasks completed.' -ForegroundColor Green
