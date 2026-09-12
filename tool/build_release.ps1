$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseConfigPath = Join-Path $projectRoot 'config.release.json'
$signingConfigPath = Join-Path $projectRoot 'android\key.properties'

if (-not (Test-Path -LiteralPath $releaseConfigPath)) {
    throw 'Missing ignored config.release.json.'
}
if (-not (Test-Path -LiteralPath $signingConfigPath)) {
    throw 'Missing ignored android/key.properties.'
}

$releaseConfig = Get-Content -LiteralPath $releaseConfigPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($releaseConfig.REVENUECAT_ANDROID_KEY)) {
    throw 'REVENUECAT_ANDROID_KEY is required for a production build.'
}
$privacyUri = $null
if (-not [Uri]::TryCreate(
        [string]$releaseConfig.PRIVACY_POLICY_URL,
        [UriKind]::Absolute,
        [ref]$privacyUri
    ) -or $privacyUri.Scheme -ne 'https') {
    throw 'PRIVACY_POLICY_URL must be an active public HTTPS URL.'
}

Push-Location $projectRoot
try {
    flutter pub get
    flutter analyze
    flutter test
    flutter build appbundle --release --dart-define-from-file=config.release.json
} finally {
    Pop-Location
}
