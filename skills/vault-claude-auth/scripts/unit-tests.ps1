# unit-tests.ps1
# Direct tests for claude-auth-core.ps1 plus the expiry script against a
# synthetic credential file. The relay's Drive action runs a real login and is
# exercised by hand per SKILL.md. Test state is a plain temp folder.

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')
. (Join-Path $PSScriptRoot 'claude-auth-core.ps1')

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "claude-auth-test-$(Get-Random)"
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Reset-TestFolder {
    if (Test-Path $testRoot) { Remove-Item -Recurse -Force $testRoot }
    New-Item -ItemType Directory -Path $testRoot | Out-Null
}

$now = [datetime]::new(2026, 10, 11, 12, 0, 0, [DateTimeKind]::Utc)
function New-CredentialJson([datetime]$RefreshAt, [datetime]$AccessAt) {
    $r = [DateTimeOffset]::new($RefreshAt).ToUnixTimeMilliseconds()
    $a = [DateTimeOffset]::new($AccessAt).ToUnixTimeMilliseconds()
    "{`"claudeAiOauth`":{`"accessToken`":`"x`",`"refreshToken`":`"y`",`"expiresAt`":$a,`"refreshTokenExpiresAt`":$r,`"subscriptionType`":`"max`"}}"
}

# ---------------------------------------------------------------------------
Write-Host "`nGet-CredentialExpiry:"

Run-Test 'counts whole days to the refresh expiry' {
    $json = New-CredentialJson $now.AddDays(41).AddHours(5) $now.AddHours(2)
    $e = Get-CredentialExpiry -Json $json -Now $now
    $e.Found -and $e.DaysRemaining -eq 41 -and $e.AccessExpiresAt -eq $now.AddHours(2)
}

Run-Test 'goes negative once expired' {
    $e = Get-CredentialExpiry -Json (New-CredentialJson $now.AddDays(-2) $now) -Now $now
    $e.Found -and $e.DaysRemaining -eq -2
}

Run-Test 'reports not found for empty, invalid, and tokenless input' {
    (-not (Get-CredentialExpiry -Json '' -Now $now).Found) -and
    (-not (Get-CredentialExpiry -Json 'not json' -Now $now).Found) -and
    (-not (Get-CredentialExpiry -Json '{"other":1}' -Now $now).Found) -and
    (-not (Get-CredentialExpiry -Json '{"claudeAiOauth":{"accessToken":"x"}}' -Now $now).Found)
}

# ---------------------------------------------------------------------------
Write-Host "`nFind-OAuthUrl:"

$esc = [char]27
$sampleUrl = 'https://claude.com/cai/oauth/authorize?code=true&client_id=abc&state=XyZ-1'

Run-Test 'extracts the URL from an OSC 8 hyperlink without bleeding into the second copy' {
    $line = "If the browser didn't open, visit: $esc]8;;$sampleUrl$esc\$sampleUrl$esc]8;;$esc\"
    (Find-OAuthUrl $line) -eq $sampleUrl
}

Run-Test 'extracts a plain URL and stops at whitespace' {
    (Find-OAuthUrl "visit: $sampleUrl then paste") -eq $sampleUrl
}

Run-Test 'returns null when no URL is present' {
    $null -eq (Find-OAuthUrl 'Opening browser to sign in...') -and $null -eq (Find-OAuthUrl '')
}

# ---------------------------------------------------------------------------
Write-Host "`nRemove-AnsiEscapes / Get-LastOutputLine:"

Run-Test 'strips CSI colours and OSC 8 wrappers' {
    $t = "$esc[32mLogged in$esc[0m as $esc]8;;https://x$esc\you$esc]8;;$esc\"
    (Remove-AnsiEscapes $t) -eq 'Logged in as you'
}

Run-Test 'last line skips trailing blanks and prompt whitespace' {
    (Get-LastOutputLine "first`r`n$esc[1mLogged in successfully$esc[0m`r`n`r`n   ") -eq 'Logged in successfully'
}

# ---------------------------------------------------------------------------
Write-Host "`nRelay state:"

Run-Test 'state round-trips through the file' {
    $p = Join-Path $testRoot 'state.json'
    Write-RelayState -Path $p -State @{ phase = 'awaiting-approval'; driverPid = 123; url = $sampleUrl }
    $s = Read-RelayState -Path $p
    $s.phase -eq 'awaiting-approval' -and $s.driverPid -eq 123 -and $s.url -eq $sampleUrl -and -not (Test-Path "$p.tmp")
}

Run-Test 'missing or corrupt state reads as null' {
    New-TestFile 'bad.json' '{not json'
    $null -eq (Read-RelayState -Path (Join-Path $testRoot 'none.json')) -and
    $null -eq (Read-RelayState -Path (Join-Path $testRoot 'bad.json'))
}

Run-Test 'phase resolves idle, stale, in-flight, and terminal states' {
    $inflight = [pscustomobject]@{ phase = 'awaiting-approval' }
    $done = [pscustomobject]@{ phase = 'done' }
    (Resolve-RelayPhase -State $null -DriverAlive $false) -eq 'idle' -and
    (Resolve-RelayPhase -State $inflight -DriverAlive $true) -eq 'awaiting-approval' -and
    (Resolve-RelayPhase -State $inflight -DriverAlive $false) -eq 'stale' -and
    (Resolve-RelayPhase -State $done -DriverAlive $false) -eq 'done'
}

Run-Test 'Test-RelayInFlight covers exactly the three live phases' {
    (Test-RelayInFlight 'starting') -and (Test-RelayInFlight 'awaiting-approval') -and (Test-RelayInFlight 'submitting') -and
    -not (Test-RelayInFlight 'done') -and -not (Test-RelayInFlight 'stale') -and -not (Test-RelayInFlight 'idle')
}

# ---------------------------------------------------------------------------
Write-Host "`nclaude-auth-expiry.ps1:"

$expiryScript = Join-Path $PSScriptRoot 'claude-auth-expiry.ps1'
$pwsh = (Get-Process -Id $PID).Path
# Run as a child pwsh so stdout and the exit code are captured like a launcher would see them.
function Invoke-Expiry { param([string[]]$ScriptArgs) (& $pwsh -NoProfile -File $expiryScript @ScriptArgs 2>&1 | Out-String) }

Run-Test 'prints days and exits 0 against a synthetic credential file' {
    $cred = Join-Path $testRoot 'cred.json'
    New-TestFile 'cred.json' (New-CredentialJson ([datetime]::UtcNow.AddDays(30).AddHours(1)) ([datetime]::UtcNow))
    $lines = Invoke-Expiry @('-CredentialPath', $cred)
    $LASTEXITCODE -eq 0 -and $lines -match 'Status: ok' -and $lines -match 'DaysRemaining: 30'
}

Run-Test '-Json emits one object and never a token' {
    $cred = Join-Path $testRoot 'cred.json'
    New-TestFile 'cred.json' (New-CredentialJson ([datetime]::UtcNow.AddDays(5)) ([datetime]::UtcNow))
    $raw = Invoke-Expiry @('-CredentialPath', $cred, '-Json')
    $o = $raw | ConvertFrom-Json
    $o.Status -eq 'ok' -and $o.DaysRemaining -eq 4 -and $raw -cnotmatch '"accessToken"|"refreshToken"'
}

Run-Test 'missing file reports missing and exits 2' {
    $lines = Invoke-Expiry @('-CredentialPath', (Join-Path $testRoot 'none.json'))
    $LASTEXITCODE -eq 2 -and $lines -match 'Status: missing'
}

# ---------------------------------------------------------------------------
if (Test-Path $testRoot) { Remove-Item -Recurse -Force $testRoot }
Write-TestSummary
