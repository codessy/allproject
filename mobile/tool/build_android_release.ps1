param(
    [ValidateSet("stage", "prod")]
    [string]$Flavor = "prod",
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,
    [string]$DevLoopbackHost = "localhost",
    [int]$BuildNumber = 0,
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

$resolvedLoopbackHost = $DevLoopbackHost
if ([string]::IsNullOrWhiteSpace($resolvedLoopbackHost) -or $resolvedLoopbackHost -eq "localhost") {
    try {
        $apiUri = [Uri]$ApiBaseUrl
        if (-not [string]::IsNullOrWhiteSpace($apiUri.Host) -and $apiUri.Host -ne "localhost") {
            $resolvedLoopbackHost = $apiUri.Host
        }
    } catch {
        # Keep provided fallback when URL parsing fails.
    }
}

Write-Step "Using DEV_LOOPBACK_HOST=$resolvedLoopbackHost"

Write-Step "Writing temporary dart-define file"
$json = @{
    API_BASE_URL = $ApiBaseUrl
    DEV_LOOPBACK_HOST = $resolvedLoopbackHost
} | ConvertTo-Json
Set-Content -Path $tempEnv -Value $json -Encoding UTF8

Write-Step "Building Android appbundle ($Flavor)"
Push-Location $projectRoot
try {
    flutter pub get
    $commonArgs = @("--release", "--flavor", $Flavor, "--dart-define-from-file=$tempEnv")
    if ($BuildNumber -gt 0) {
        Write-Step "Using build number $BuildNumber"
        $commonArgs += "--build-number=$BuildNumber"
    }
    flutter build appbundle @commonArgs
    if ($BuildApk) {
        Write-Step "Building Android APK ($Flavor)"
        flutter build apk @commonArgs
    }
}
finally {
    Pop-Location
    Remove-Item $tempEnv -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Release build completed for flavor '$Flavor'." -ForegroundColor Green
