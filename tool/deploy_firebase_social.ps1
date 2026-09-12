$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseConfigPath = Join-Path $projectRoot 'config.release.json'
$accountGuard = Join-Path $PSScriptRoot 'assert_firebase_account.ps1'

& $accountGuard -ReleaseConfigPath $releaseConfigPath
$releaseConfig = Get-Content -LiteralPath $releaseConfigPath -Raw |
    ConvertFrom-Json
$projectId = [string]$releaseConfig.FIREBASE_PROJECT_ID
if ([string]::IsNullOrWhiteSpace($projectId) -or $projectId.StartsWith('demo-')) {
    throw 'FIREBASE_PROJECT_ID must name the real production Firebase project.'
}

Push-Location $projectRoot
try {
    npm --prefix functions test
    $npxCommand = (Get-Command npx.cmd -ErrorAction Stop).Source
    & $npxCommand --yes firebase-tools@latest deploy `
        --project $projectId `
        --only functions,firestore:rules,firestore:indexes
} finally {
    Pop-Location
}
