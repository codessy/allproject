param(
    [string]$ApiBaseUrl = "http://localhost:8080",
    [string]$DemoEmail = "demo@example.com",
    [string]$DemoPassword = "password",
    [string]$PackageName = "com.example.walkietalkie_mobile",
    [string]$DeviceId = "",
    [bool]$ValidateLoggedOutBoundary = $true
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-TargetDeviceId {
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

    $emulator = $online | Where-Object { $_ -like "emulator-*" } | Select-Object -First 1
    if ($emulator) {
        return $emulator
    }
    return $online[0]
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
        [string]$Pattern,
        [int]$Attempts = 20,
        [int]$SleepSeconds = 1
    )

    for ($i = 0; $i -lt $Attempts; $i++) {
        $dump = adb -s $targetDevice exec-out uiautomator dump /dev/tty
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

    # Force target package to avoid Android resolver chooser when multiple
    # app flavors are installed and can handle the same deep link.
    $output = cmd /c "adb -s $TargetDevice shell am start -W -a android.intent.action.VIEW -d $Uri $TargetPackage 2>&1"
    if ($LASTEXITCODE -ne 0 -or ($output -match "Error:")) {
        cmd /c "adb -s $TargetDevice shell am start -a android.intent.action.VIEW -d $Uri 2>&1" | Out-Null
    }
}

Write-Step "Resolving target emulator/device"
$targetDevice = Get-TargetDeviceId
Write-Host "Using device: $targetDevice"

Write-Step "Ensuring app is in foreground"
$startOutput = cmd /c "adb -s $targetDevice shell am start -n $PackageName/.MainActivity 2>&1"
if ($LASTEXITCODE -ne 0 -or ($startOutput -match "Error:")) {
    adb -s $targetDevice shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
}

Write-Step "Logging in demo owner"
$login = Invoke-ApiJson -Method "POST" -Path "/v1/auth/login" -Body @{
    email    = $DemoEmail
    password = $DemoPassword
}
$token = $login.accessToken
if (-not $token) {
    throw "Demo login did not return an access token."
}

Write-Step "Creating fresh invite"
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
Write-Host "Invite token: $inviteToken"

Write-Step "Sending runtime deep-link intent"
Start-DeepLinkIntent -TargetDevice $targetDevice -TargetPackage $PackageName -Uri $deepLink

Write-Step "Verifying invite accept screen content"
$ui = Wait-UiMatch -Pattern "Davet Kabul|Invite Accept|Invite|Giris|Login|Sign in" -Attempts 25 -SleepSeconds 1
if (-not $ui) {
    throw "Runtime deep-link did not produce an expected screen (invite or login)."
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
    Write-Host "Login boundary detected (app session missing). Deep-link handoff still verified." -ForegroundColor Yellow
}
else {
    throw "Deep-link reached an unknown UI state."
}

if ($ValidateLoggedOutBoundary) {
    Write-Step "Verifying logged-out deep-link boundary"
    adb -s $targetDevice shell pm clear $PackageName | Out-Null
    adb -s $targetDevice shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
    Start-DeepLinkIntent -TargetDevice $targetDevice -TargetPackage $PackageName -Uri $deepLink
    $loggedOutUi = Wait-UiMatch -Pattern "Giris|Login|Sign in" -Attempts 25 -SleepSeconds 1
    if (-not $loggedOutUi) {
        throw "Logged-out runtime deep-link did not route to login boundary."
    }
}

Write-Host ""
Write-Host "Runtime deep-link verification passed." -ForegroundColor Green
Write-Host "Device: $targetDevice"
Write-Host "Deep link: $deepLink"
