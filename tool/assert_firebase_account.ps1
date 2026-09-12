param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseConfigPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ReleaseConfigPath)) {
    throw 'Missing ignored config.release.json.'
}

$releaseConfig = Get-Content -LiteralPath $ReleaseConfigPath -Raw |
    ConvertFrom-Json
$expectedEmail = [string]$releaseConfig.FIREBASE_OPERATOR_EMAIL
if ([string]::IsNullOrWhiteSpace($expectedEmail)) {
    throw 'FIREBASE_OPERATOR_EMAIL must name the designated Firebase operator.'
}

# Capture the JSON instead of printing it: firebase login:list includes OAuth
# credentials that must never be written to CI or terminal logs.
$npxCommand = (Get-Command npx.cmd -ErrorAction Stop).Source
$loginJson = & $npxCommand --yes firebase-tools@latest login:list --json 2>&1 |
    Out-String
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to verify the Firebase CLI account.'
}
try {
    $login = $loginJson | ConvertFrom-Json
} catch {
    throw 'Firebase CLI returned an unreadable account response.'
}

$emails = @(
    $login.result |
        ForEach-Object { [string]$_.user.email } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($emails.Count -ne 1 -or
    -not $emails[0].Equals($expectedEmail, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Firebase CLI is not authenticated only as the designated Harshita account.'
}

Write-Output 'Firebase operator account verified.'
