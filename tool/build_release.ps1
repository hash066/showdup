$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseConfigPath = Join-Path $projectRoot 'config.release.json'
$signingConfigPath = Join-Path $projectRoot 'android\key.properties'
$originalGradleUserHome = $env:GRADLE_USER_HOME

# Keep Gradle's mutable transforms outside the checkout. On Windows a global
# Gradle home can itself be a junction into an old project cache, which makes
# release asset merging fail when Gradle attempts an atomic directory move.
if ([string]::IsNullOrWhiteSpace($originalGradleUserHome)) {
    $workspaceParent = Split-Path -Parent $projectRoot
    $env:GRADLE_USER_HOME = Join-Path $workspaceParent 'Showdup-gradle-release'
}

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
# RevenueCat's public SDK key for a Google Play app starts with goog_. A Test
# Store key (test_) or another platform's key would ship a dead paywall.
$revenueCatKey = [string]$releaseConfig.REVENUECAT_ANDROID_KEY
if (-not $revenueCatKey.StartsWith('goog_') -or $revenueCatKey.Contains('REPLACE')) {
    throw 'REVENUECAT_ANDROID_KEY must be the real Google Play public SDK key (goog_...).'
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
    # Analyze the Dart source surfaces explicitly. This avoids recursing into
    # ignored Android/Flutter build caches that can exist under the repository
    # on Windows and make a root-level analyzer invocation appear to hang.
    flutter analyze lib test tool
    flutter test
    flutter build appbundle --release --dart-define-from-file=config.release.json
} finally {
    Pop-Location
    if ([string]::IsNullOrWhiteSpace($originalGradleUserHome)) {
        Remove-Item Env:GRADLE_USER_HOME -ErrorAction SilentlyContinue
    } else {
        $env:GRADLE_USER_HOME = $originalGradleUserHome
    }
}
