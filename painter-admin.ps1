[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $AdminArguments
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$adminEnv = Join-Path $projectRoot '.env.admin'

if (Test-Path -LiteralPath $adminEnv) {
    foreach ($line in Get-Content -LiteralPath $adminEnv) {
        $value = $line.Trim()
        if ($value.Length -eq 0 -or $value.StartsWith('#')) { continue }
        $parts = $value.Split('=', 2)
        if ($parts.Length -ne 2) { throw "Invalid line in .env.admin: $line" }
        [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), 'Process')
    }
}

Push-Location $projectRoot
try {
    $adminExe = Join-Path $projectRoot 'painter-admin.exe'
    $adminSource = Join-Path $projectRoot 'tool\painter_admin\painter_admin.dart'
    $sourceFiles = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tool\painter_admin') -Recurse -Filter '*.dart'
    $needsBuild = -not (Test-Path -LiteralPath $adminExe)
    if (-not $needsBuild) {
        $exeTimestamp = (Get-Item -LiteralPath $adminExe).LastWriteTimeUtc
        $needsBuild = $null -ne ($sourceFiles | Where-Object {
            $_.LastWriteTimeUtc -gt $exeTimestamp
        } | Select-Object -First 1)
    }

    if ($needsBuild) {
        Write-Host 'Building Painter Reference administration console...'
        & dart compile exe $adminSource -o $adminExe
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    & $adminExe @AdminArguments
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}