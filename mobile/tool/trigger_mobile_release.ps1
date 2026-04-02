param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,
    [ValidateSet("stage", "prod")]
    [string]$Flavor = "stage",
    [switch]$BuildApk,
    [switch]$PublishInternal
)

$ErrorActionPreference = "Stop"
$script:GhCommand = $null

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
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

Write-Step "Preparing GitHub CLI"
Initialize-GhCommand

Write-Step "Checking GitHub authentication"
Invoke-Gh auth status

Write-Step "Triggering mobile-release workflow"
Invoke-Gh workflow run mobile-release.yml `
    --repo $Repository `
    -f flavor=$Flavor `
    -f build_apk=$($BuildApk.IsPresent.ToString().ToLowerInvariant()) `
    -f publish_internal=$($PublishInternal.IsPresent.ToString().ToLowerInvariant())

Write-Step "Fetching latest workflow run"
Invoke-Gh run list --repo $Repository --workflow mobile-release.yml --limit 1
