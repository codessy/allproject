param(
    [string]$ApiBaseUrl = "http://localhost:8080",
    [string]$DemoEmail = "demo@example.com",
    [string]$DemoPassword = "password",
    [string]$PackageName = "com.example.walkietalkie_mobile.dev",
    [string]$DeviceId = "",
    [switch]$AllowEmulator
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-TargetDevice {
    if ($DeviceId -and $DeviceId.Trim().Length -gt 0) {
        return $DeviceId.Trim()
    }

    $lines = adb devices | Select-Object -Skip 1
    $online = @()
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed -match "^([^\s]+)\s+device$") {
            $online += $Matches[1]
        }
    }
    if ($online.Count -eq 0) {
        throw "No online adb device found."
    }

    if ($AllowEmulator) {
        return $online[0]
    }

    $physical = $online | Where-Object { $_ -notlike "emulator-*" } | Select-Object -First 1
    if (-not $physical) {
        throw "No physical device found. Connect a real Android device or pass -AllowEmulator."
    }
    return $physical
}

function Invoke-ApiJson {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Headers,
        [object]$Body
    )

    $uri = "$ApiBaseUrl$Path"
    if ($PSBoundParameters.ContainsKey("Body")) {
        $jsonBody = $Body | ConvertTo-Json -Depth 10
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $Headers -ContentType "application/json" -Body $jsonBody
    }
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $Headers
}

function Wait-UiMatch {
    param(
        [string]$TargetDevice,
        [string]$Pattern,
        [int]$Attempts = 30,
        [int]$SleepSeconds = 1
    )

    for ($i = 0; $i -lt $Attempts; $i++) {
        $dump = adb -s $TargetDevice exec-out uiautomator dump /dev/tty
        if ($dump -match $Pattern) {
            return $dump
        }
        Start-Sleep -Seconds $SleepSeconds
    }
    return $null
}

function Start-DeepLinkIntent {
    param(
        [string]$TargetDevice,
        [string]$TargetPackage,
        [string]$Uri
    )

    # Force package to avoid resolver chooser when multiple flavors are installed.
    $output = cmd /c "adb -s $TargetDevice shell am start -W -a android.intent.action.VIEW -d $Uri $TargetPackage 2>&1"
    if ($LASTEXITCODE -ne 0 -or ($output -match "Error:")) {
        cmd /c "adb -s $TargetDevice shell am start -a android.intent.action.VIEW -d $Uri 2>&1" | Out-Null
    }
}

Write-Step "Selecting target device"
$targetDevice = Get-TargetDevice
Write-Host "Using device: $targetDevice"

Write-Step "Logging in backend and creating fresh invite"
$login = Invoke-ApiJson -Method "POST" -Path "/v1/auth/login" -Body @{
    email    = $DemoEmail
    password = $DemoPassword
}
$token = $login.accessToken
if (-not $token) {
    throw "Demo login did not return an access token."
}

$channels = Invoke-ApiJson -Method "GET" -Path "/v1/channels" -Headers @{
    Authorization = "Bearer $token"
}
$channel = $channels.channels | Select-Object -First 1
if (-not $channel) {
    throw "No channel returned for demo owner."
}
$invite = Invoke-ApiJson -Method "POST" -Path "/v1/channels/$($channel.id)/invites" -Headers @{
    Authorization = "Bearer $token"
} -Body @{
    maxUses        = 1
    expiresInHours = 1
}
$inviteToken = $invite.inviteToken.ToString().Trim()
if (-not $inviteToken) {
    throw "Invite creation did not return an invite token."
}
$deepLink = "walkietalkie://invite/open?invite=$inviteToken"

Write-Step "Installing latest dev APK"
$apkPath = Join-Path $PSScriptRoot "..\build\app\outputs\flutter-apk\app-dev-debug.apk"
if (-not (Test-Path $apkPath)) {
    throw "Missing APK at $apkPath. Build first: flutter build apk --debug --flavor dev --dart-define-from-file=env/dev.json"
}
adb -s $targetDevice install -r $apkPath | Out-Null

Write-Step "Launching app"
cmd /c "adb -s $targetDevice shell am start -n $PackageName/.MainActivity 2>&1" | Out-Null

Write-Step "Sending runtime deep-link"
Start-DeepLinkIntent -TargetDevice $targetDevice -TargetPackage $PackageName -Uri $deepLink

Write-Step "Verifying invite screen and token prefill"
$ui = Wait-UiMatch -TargetDevice $targetDevice -Pattern "Davet Kabul|Invite Accept|Invite|Giris|Login|Sign in" -Attempts 30 -SleepSeconds 1
if (-not $ui) {
    throw "Expected deep-link outcome did not appear (invite or login screen)."
}

$inviteVisible = $ui -match "Davet Kabul|Invite Accept|Invite"
$loginVisible = $ui -match "Giris|Login|Sign in"

if ($inviteVisible) {
    if ($ui -notmatch [regex]::Escape($inviteToken)) {
        throw "Invite token was not prefilled on InviteAcceptScreen."
    }
    Write-Host "Invite screen detected with token prefill."
}
elseif ($loginVisible) {
    Write-Host "Login boundary detected (device app session missing)." -ForegroundColor Yellow
}
else {
    throw "Deep-link reached an unknown UI state."
}

Write-Host ""
Write-Host "Physical device smoke passed." -ForegroundColor Green
Write-Host "Device: $targetDevice"
Write-Host "Deep link: $deepLink"
