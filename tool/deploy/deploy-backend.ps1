[CmdletBinding()]
param(
    [string[]]$Functions = @(),
    [switch]$AllFunctions,
    [switch]$SkipMigrations
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    throw 'npx was not found. Install Node.js before deploying Supabase.'
}

if (-not $SkipMigrations) {
    Write-Host 'Applying pending Supabase migrations...'
    & npx supabase db push
    if ($LASTEXITCODE -ne 0) { throw 'Supabase migration deployment failed.' }
}

if ($AllFunctions) {
    Write-Host 'Deploying all Supabase Edge Functions...'
    & npx supabase functions deploy --use-api
    if ($LASTEXITCODE -ne 0) { throw 'Edge Function deployment failed.' }
} elseif ($Functions.Count -gt 0) {
    Write-Host "Deploying Edge Functions: $($Functions -join ', ')"
    & npx supabase functions deploy @Functions --use-api
    if ($LASTEXITCODE -ne 0) { throw 'Edge Function deployment failed.' }
} else {
    Write-Host 'No Edge Functions selected. Use -AllFunctions or -Functions name1,name2.'
}

Write-Host 'Backend deployment completed.' -ForegroundColor Green
