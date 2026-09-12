$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseConfigPath = Join-Path $projectRoot 'config.release.json'
$privacyPagePath = Join-Path $projectRoot 'public\privacy\index.html'

if (-not (Test-Path -LiteralPath $releaseConfigPath)) {
    throw 'Missing ignored config.release.json.'
}
if (-not (Test-Path -LiteralPath $privacyPagePath)) {
    throw 'Missing public/privacy/index.html.'
}

$releaseConfig = Get-Content -LiteralPath $releaseConfigPath -Raw | ConvertFrom-Json
$projectId = [string]$releaseConfig.FIREBASE_PROJECT_ID
if ([string]::IsNullOrWhiteSpace($projectId) -or $projectId.StartsWith('demo-')) {
    throw 'FIREBASE_PROJECT_ID must name the real production Firebase project.'
}
& (Join-Path $PSScriptRoot 'assert_firebase_account.ps1') `
    -ReleaseConfigPath $releaseConfigPath

Push-Location $projectRoot
try {
    $npxCommand = (Get-Command npx.cmd -ErrorAction Stop).Source
    & $npxCommand --yes firebase-tools@latest deploy `
        --only hosting --project $projectId
} finally {
    Pop-Location
}
