param(
    [string]$ApiBaseUrl = "http://localhost:8080"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Net.Http
$script:HttpClient = [System.Net.Http.HttpClient]::new()

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-HttpJson {
    param(
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method,
        [string]$Path,
        [hashtable]$Headers = @{},
        [object]$Body = $null,
        [int]$ExpectedStatusCode = 200
    )

    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::$Method,
        "$ApiBaseUrl$Path"
    )

    foreach ($key in $Headers.Keys) {
        $null = $request.Headers.TryAddWithoutValidation($key, [string]$Headers[$key])
    }

    if ($null -ne $Body) {
        $jsonBody = $Body | ConvertTo-Json -Depth 10
        $request.Content = [System.Net.Http.StringContent]::new(
            $jsonBody,
            [System.Text.Encoding]::UTF8,
            "application/json"
        )
    }

    $response = $script:HttpClient.SendAsync($request).GetAwaiter().GetResult()
    $statusCode = [int]$response.StatusCode
    $responseBody = ""
    if ($response.Content) {
        $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    }

    if ($statusCode -ne $ExpectedStatusCode) {
        throw "API call failed: [$Method] $Path => HTTP $statusCode $responseBody"
    }

    if ([string]::IsNullOrWhiteSpace($responseBody)) {
        return $null
    }

    try {
        return $responseBody | ConvertFrom-Json
    }
    catch {
        return $responseBody
    }
}

function Invoke-Api {
    param(
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method,
        [string]$Path,
        [hashtable]$Headers = @{},
        [object]$Body = $null
    )

    return Invoke-HttpJson -Method $Method -Path $Path -Headers $Headers -Body $Body -ExpectedStatusCode 200
}

function Invoke-ApiCreated {
    param(
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method,
        [string]$Path,
        [hashtable]$Headers = @{},
        [object]$Body = $null
    )

    return Invoke-HttpJson -Method $Method -Path $Path -Headers $Headers -Body $Body -ExpectedStatusCode 201
}

function Invoke-ApiExpectFailure {
    param(
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method,
        [string]$Path,
        [int]$ExpectedStatusCode,
        [hashtable]$Headers = @{},
        [object]$Body = $null
    )

    try {
        $null = Invoke-HttpJson -Method $Method -Path $Path -Headers $Headers -Body $Body -ExpectedStatusCode $ExpectedStatusCode
    }
    catch {
        if ($_.Exception.Message -notmatch "HTTP $ExpectedStatusCode ") {
            throw
        }
    }
}

function New-RandomEmail {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    $suffix = Get-Random -Minimum 1000 -Maximum 9999
    return "smoke+$stamp$suffix@example.com"
}

Write-Step "Checking API health"
$health = Invoke-Api -Method GET -Path "/healthz"
if ($health.status -ne "ok") {
    throw "Health check failed."
}

$inviteeEmail = New-RandomEmail
$inviteePassword = "Password123!"

Write-Step "Logging in seeded demo owner"
$demoLogin = Invoke-Api -Method POST -Path "/v1/auth/login" -Body @{
    email    = "demo@example.com"
    password = "password"
}
$demoToken = $demoLogin.accessToken
if (-not $demoToken) {
    throw "Demo login did not return an access token."
}

Write-Step "Registering invitee account"
$inviteeRegister = Invoke-ApiCreated -Method POST -Path "/v1/auth/register" -Body @{
    email       = $inviteeEmail
    displayName = "Smoke Invitee"
    password    = $inviteePassword
}
if (-not $inviteeRegister.accessToken) {
    throw "Invitee registration did not return an access token."
}

Write-Step "Listing demo channels"
$demoChannels = Invoke-Api -Method GET -Path "/v1/channels" -Headers @{
    Authorization = "Bearer $demoToken"
}

$channel = $demoChannels.channels | Select-Object -First 1
if (-not $channel) {
    throw "No channel returned for demo owner."
}
$channelId = $channel.id.ToString().Trim()

Write-Host "Using channel: $($channel.name) [$channelId]"

Write-Step "Creating invite for selected channel"
$inviteResponse = Invoke-ApiCreated -Method POST -Path "/v1/channels/$channelId/invites" -Headers @{
    Authorization = "Bearer $demoToken"
} -Body @{
    maxUses        = 1
    expiresInHours = 1
}

$inviteToken = $inviteResponse.inviteToken.ToString().Trim()
if (-not $inviteToken) {
    throw "Invite creation did not return an invite token."
}

Write-Step "Logging in invitee account"
$inviteeLogin = Invoke-Api -Method POST -Path "/v1/auth/login" -Body @{
    email    = $inviteeEmail
    password = $inviteePassword
}
$inviteeToken = $inviteeLogin.accessToken
if (-not $inviteeToken) {
    throw "Invitee login did not return an access token."
}

Write-Step "Accepting invite with invitee"
$acceptResponse = Invoke-Api -Method POST -Path "/v1/invites/$inviteToken/accept" -Headers @{
    Authorization = "Bearer $inviteeToken"
}
if (-not $acceptResponse.joined) {
    throw "Invite acceptance did not confirm membership."
}

Write-Step "Verifying invitee channel membership"
$inviteeChannels = Invoke-Api -Method GET -Path "/v1/channels" -Headers @{
    Authorization = "Bearer $inviteeToken"
}

$joinedChannel = $inviteeChannels.channels | Where-Object { $_.id -eq $channelId } | Select-Object -First 1
if (-not $joinedChannel) {
    throw "Invitee does not see the joined channel after accept."
}

Write-Step "Creating and revoking a second invite"
$revokeInviteResponse = Invoke-ApiCreated -Method POST -Path "/v1/channels/$channelId/invites" -Headers @{
    Authorization = "Bearer $demoToken"
} -Body @{
    maxUses        = 1
    expiresInHours = 1
}

$revokeInviteId = $revokeInviteResponse.invite.id.ToString().Trim()
$revokeInviteToken = $revokeInviteResponse.inviteToken.ToString().Trim()
if (-not $revokeInviteId -or -not $revokeInviteToken) {
    throw "Second invite did not return the required id/token."
}

$null = Invoke-Api -Method POST -Path "/v1/channels/$channelId/invites/$revokeInviteId/revoke" -Headers @{
    Authorization = "Bearer $demoToken"
}

Write-Step "Confirming revoked invite cannot be accepted"
Invoke-ApiExpectFailure -Method POST -Path "/v1/invites/$revokeInviteToken/accept" -ExpectedStatusCode 404 -Headers @{
    Authorization = "Bearer $inviteeToken"
}

Write-Step "Removing invitee from the channel"
$inviteeUserId = $inviteeRegister.user.id.ToString().Trim()
$null = Invoke-Api -Method DELETE -Path "/v1/channels/$channelId/members/$inviteeUserId" -Headers @{
    Authorization = "Bearer $demoToken"
}

Write-Step "Verifying invitee no longer sees the channel"
$inviteeChannelsAfterRemoval = Invoke-Api -Method GET -Path "/v1/channels" -Headers @{
    Authorization = "Bearer $inviteeToken"
}
$stillJoinedChannel = $inviteeChannelsAfterRemoval.channels | Where-Object { $_.id -eq $channelId } | Select-Object -First 1
if ($stillJoinedChannel) {
    throw "Invitee still sees the channel after member removal."
}

Write-Host ""
Write-Host "Smoke test passed." -ForegroundColor Green
Write-Host "Invitee: $inviteeEmail"
Write-Host "Channel: $($channel.name) [$channelId]"
