param(
    [ValidateSet("stage", "prod")]
    [string]$Flavor = "prod",
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,
    [string]$DevLoopbackHost = "localhost",
    [switch]$BuildApk
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$tempRoot = [System.IO.Path]::GetTempPath()
$tempEnv = Join-Path $tempRoot "walkietalkie-$Flavor-release-env.json"

Write-Step "Writing temporary dart-define file"
$json = @{
    API_BASE_URL = $ApiBaseUrl
    DEV_LOOPBACK_HOST = $DevLoopbackHost
} | ConvertTo-Json
Set-Content -Path $tempEnv -Value $json -Encoding UTF8

Write-Step "Building Android appbundle ($Flavor)"
Push-Location $projectRoot
try {
    flutter pub get
    flutter build appbundle --release --flavor $Flavor --dart-define-from-file=$tempEnv
    if ($BuildApk) {
        Write-Step "Building Android APK ($Flavor)"
        flutter build apk --release --flavor $Flavor --dart-define-from-file=$tempEnv
    }
}
finally {
    Pop-Location
    Remove-Item $tempEnv -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Release build completed for flavor '$Flavor'." -ForegroundColor Green
