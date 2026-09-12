$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sandboxConfigPath = Join-Path $projectRoot 'config.sandbox.json'

if (-not (Test-Path -LiteralPath $sandboxConfigPath)) {
    throw 'Missing ignored config.sandbox.json. Start with config.sandbox.example.json.'
}

$sandboxConfig = Get-Content -LiteralPath $sandboxConfigPath -Raw |
    ConvertFrom-Json
if (-not ([string]$sandboxConfig.REVENUECAT_ANDROID_KEY).StartsWith('test_')) {
    throw 'The Pro sandbox build requires a RevenueCat Test Store key.'
}

Push-Location $projectRoot
try {
    flutter build apk --debug --dart-define-from-file=config.sandbox.json
} finally {
    Pop-Location
}
