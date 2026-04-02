param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,
    [Parameter(Mandatory = $true)]
    [string]$StageApiBaseUrl,
    [Parameter(Mandatory = $true)]
    [string]$ProdApiBaseUrl,
    [string]$KeystorePropertiesPath = ".\android\keystore.properties",
    [string]$KeystoreFilePath = ".\android\keystore\upload-keystore.jks",
    [string]$PlayServiceAccountJsonPath
)

$ErrorActionPreference = "Stop"
$script:GhCommand = $null

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Initialize-GhCommand {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh) {
        $script:GhCommand = $gh.Source
        return
    }

    $portableRoot = Join-Path $env:TEMP "gh-portable"
    $zipPath = Join-Path $portableRoot "gh.zip"
    $version = "2.89.0"
    $downloadUrl = "https://github.com/cli/cli/releases/download/v$version/gh_${version}_windows_amd64.zip"

    if (-not (Test-Path $portableRoot)) {
        New-Item -ItemType Directory -Path $portableRoot | Out-Null
    }

    if (-not (Test-Path $zipPath)) {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
    }
    Expand-Archive -Path $zipPath -DestinationPath $portableRoot -Force
    $portableExe = Get-ChildItem -Path $portableRoot -Recurse -Filter gh.exe | Select-Object -First 1
    if (-not $portableExe) {
        throw "Failed to prepare portable gh executable."
    }
    $script:GhCommand = $portableExe.FullName
}

function Invoke-Gh {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )
    & $script:GhCommand @Args
    if ($LASTEXITCODE -ne 0) {
        throw "gh command failed: gh $($Args -join ' ')"
    }
}

function Set-GhSecretText([string]$Name, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Secret '$Name' value is empty."
    }
    $Value | & $script:GhCommand secret set $Name --repo $Repository
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set secret: $Name"
    }
}

function Set-GhSecretFile([string]$Name, [string]$Path) {
    if (-not (Test-Path $Path)) {
        throw "File not found for secret '$Name': $Path"
    }
    $content = Get-Content -Raw -Path $Path
    & $script:GhCommand secret set $Name --repo $Repository --body $content
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set secret: $Name"
    }
}

Write-Step "Validating dependencies"
Initialize-GhCommand

Write-Step "Checking GitHub authentication"
Invoke-Gh auth status

$resolvedKeystoreProps = Resolve-Path $KeystorePropertiesPath -ErrorAction Stop
$resolvedKeystoreFile = Resolve-Path $KeystoreFilePath -ErrorAction Stop

Write-Step "Setting API URL secrets"
Set-GhSecretText -Name "MOBILE_API_BASE_URL_STAGE" -Value $StageApiBaseUrl
Set-GhSecretText -Name "MOBILE_API_BASE_URL_PROD" -Value $ProdApiBaseUrl

Write-Step "Setting Android signing secrets"
Set-GhSecretFile -Name "MOBILE_ANDROID_KEYSTORE_PROPERTIES" -Path $resolvedKeystoreProps
$keystoreBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($resolvedKeystoreFile))
Set-GhSecretText -Name "MOBILE_ANDROID_KEYSTORE_BASE64" -Value $keystoreBase64

if (-not [string]::IsNullOrWhiteSpace($PlayServiceAccountJsonPath)) {
    $resolvedPlayJson = Resolve-Path $PlayServiceAccountJsonPath -ErrorAction Stop
    Write-Step "Setting Play Console service account secret"
    Set-GhSecretFile -Name "MOBILE_PLAY_SERVICE_ACCOUNT_JSON" -Path $resolvedPlayJson
}

Write-Host ""
Write-Host "GitHub release secrets configured successfully for $Repository." -ForegroundColor Green
