# Test-CalDavDiscovery.ps1
#
# Proof-of-concept spike: hand-rolled PowerShell CalDAV against caldav.icloud.com.
# Walks the standard CalDAV discovery chain (see CalDavClient.ps1) and lists the
# calendars found, to answer the open question in Plan-Vault-Calendar-Skill.md
# ("hand-rolled PowerShell vs. Python + caldav library") before committing to an
# implementation language.
#
# Credential resolution (in order): -AppleId/-AppPassword params, then Windows Credential
# Manager under target "vault-calendar:icloud" (run Set-CalDavCredential.ps1 once to
# populate it). The app-specific password comes from appleid.apple.com, not the Apple ID
# account password.
#
# Usage:
#   # Option A: rely on the credential stored via Set-CalDavCredential.ps1
#   .\Test-CalDavDiscovery.ps1
#
#   # Option B: supply credentials explicitly
#   .\Test-CalDavDiscovery.ps1 -AppleId "me@example.com" -AppPassword (Read-Host -AsSecureString)

param(
    [string]$AppleId,
    [securestring]$AppPassword
)

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-credentials.ps1')
. (Join-Path $PSScriptRoot 'CalDavClient.ps1')

if (-not $AppleId -or -not $AppPassword) {
    $Stored = Get-StoredCredential -Target "vault-calendar:icloud"
    if ($Stored) {
        if (-not $AppleId)     { $AppleId     = $Stored.UserName }
        if (-not $AppPassword) { $AppPassword = $Stored.Password }
    }
}

if (-not $AppleId -or -not $AppPassword) {
    Write-Error "No iCloud credentials found. Run .\Set-CalDavCredential.ps1 once to store them in Windows Credential Manager, or pass -AppleId/-AppPassword."
    exit 1
}

$AuthHeader = Get-CalDavAuthHeader -AppleId $AppleId -AppPassword $AppPassword

Write-Host "Discovering calendars..."
$Calendars = Get-CalDavCalendars -AuthHeader $AuthHeader

Write-Host ""
Write-Host "Found $($Calendars.Count) calendar(s):"
$Calendars | Format-Table -AutoSize
