# claude-auth-core.ps1
# Pure helpers for the vault-claude-auth scripts: credential expiry parsing,
# sign-in URL extraction, and relay state handling. Nothing here starts a
# process or touches the network, so unit-tests.ps1 covers it directly.

Set-StrictMode -Version Latest

function Get-ClaudeCredentialPath {
    Join-Path $HOME '.claude' '.credentials.json'
}

function Get-RelayStateDir {
    Join-Path $HOME '.claude-auth-relay'
}

# Property read that tolerates a missing member under strict mode.
function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

function ConvertFrom-UnixMs {
    param([long]$Ms)
    [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).UtcDateTime
}

# Parse the credential file's JSON into expiry facts. Returns
# @{ Found; RefreshExpiresAt; AccessExpiresAt; DaysRemaining }: timestamps are
# UTC DateTimes (null when absent); DaysRemaining is whole days until the
# refresh token expires, negative once it has. Found is false when the text is
# empty, not JSON, or carries no claude.ai OAuth block.
function Get-CredentialExpiry {
    param(
        [AllowEmptyString()][AllowNull()][string]$Json,
        [datetime]$Now = [datetime]::UtcNow
    )
    $result = @{ Found = $false; RefreshExpiresAt = $null; AccessExpiresAt = $null; DaysRemaining = $null }
    if ([string]::IsNullOrWhiteSpace($Json)) { return $result }
    try { $obj = $Json | ConvertFrom-Json } catch { return $result }
    $oauth = Get-Prop $obj 'claudeAiOauth'
    $refresh = Get-Prop $oauth 'refreshTokenExpiresAt'
    if ($null -eq $refresh) { return $result }
    $result.Found = $true
    $result.RefreshExpiresAt = ConvertFrom-UnixMs $refresh
    $access = Get-Prop $oauth 'expiresAt'
    if ($null -ne $access) { $result.AccessExpiresAt = ConvertFrom-UnixMs $access }
    $result.DaysRemaining = [int][math]::Floor(($result.RefreshExpiresAt - $Now.ToUniversalTime()).TotalDays)
    return $result
}

# Pull the sign-in URL out of `claude auth login` output. The CLI wraps it in
# an OSC 8 hyperlink, so the URL appears twice with escape bytes between; the
# character class stops at ESC and BEL, and the first match is returned.
function Find-OAuthUrl {
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    if ($Text -match 'https://[^\s\x1b\x07]*?/oauth/authorize\?[^\s\x1b\x07]+') { return $Matches[0] }
    return $null
}

# Strip ANSI CSI sequences and OSC 8 hyperlink wrappers so logged lines read
# as plain text.
function Remove-AnsiEscapes {
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $t = $Text -replace '\x1b\]8;;[^\x1b\x07]*(\x1b\\|\x07)', ''
    $t = $t -replace '\x1b\[[0-9;?]*[ -/]*[@-~]', ''
    return $t
}

# Last non-blank line of a block of output, cleaned of escapes.
function Get-LastOutputLine {
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $lines = (Remove-AnsiEscapes $Text) -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
    if ($lines) { return ($lines | Select-Object -Last 1).Trim() }
    return ''
}

function Read-RelayState {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { Get-Content $Path -Raw | ConvertFrom-Json } catch { $null }
}

# Write state through a temp file so a reader never sees a half-written JSON.
function Write-RelayState {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][hashtable]$State)
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, ($State | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
    Move-Item -Path $tmp -Destination $Path -Force
}

function Test-ProcessAlive {
    param($ProcessId)
    if (-not $ProcessId) { return $false }
    $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

# The phase a caller should act on. An in-flight phase whose driver process is
# gone reads as 'stale' so Start knows to replace it rather than wait on it.
function Resolve-RelayPhase {
    param($State, [bool]$DriverAlive)
    $phase = Get-Prop $State 'phase'
    if (-not $phase) { return 'idle' }
    if ($phase -in @('starting', 'awaiting-approval', 'submitting') -and -not $DriverAlive) { return 'stale' }
    return $phase
}

function Test-RelayInFlight {
    param([string]$Phase)
    $Phase -in @('starting', 'awaiting-approval', 'submitting')
}
