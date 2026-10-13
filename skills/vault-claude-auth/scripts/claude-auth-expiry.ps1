# claude-auth-expiry.ps1
# Prints how long the Claude Code login has left. The refresh token is the real
# deadline (the access token renews silently), so DaysRemaining counts to
# refreshTokenExpiresAt. Reads only the expiry fields; never prints a token.
#
# Usage:
#   .\claude-auth-expiry.ps1          Key: value lines
#   .\claude-auth-expiry.ps1 -Json    one JSON object, for the Uptime Kuma push
#
# Exit codes: 0 credential found; 2 no credential file or no OAuth block.

param(
    [switch]$Json,
    [string]$CredentialPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'claude-auth-core.ps1')

if (-not $CredentialPath) { $CredentialPath = Get-ClaudeCredentialPath }
$text = if (Test-Path $CredentialPath) { Get-Content $CredentialPath -Raw } else { '' }
$exp = Get-CredentialExpiry -Json $text

$out = [ordered]@{
    Status                = if ($exp.Found) { 'ok' } else { 'missing' }
    DaysRemaining         = $exp.DaysRemaining
    RefreshTokenExpiresAt = if ($exp.RefreshExpiresAt) { $exp.RefreshExpiresAt.ToString('o') } else { $null }
    AccessTokenExpiresAt  = if ($exp.AccessExpiresAt) { $exp.AccessExpiresAt.ToString('o') } else { $null }
}

if ($Json) {
    $out | ConvertTo-Json -Compress
} else {
    foreach ($k in $out.Keys) { Write-Output "${k}: $($out[$k])" }
}

if (-not $exp.Found) { exit 2 }
