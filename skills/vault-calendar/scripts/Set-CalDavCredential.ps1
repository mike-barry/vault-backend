# Set-CalDavCredential.ps1
#
# Interactively prompts for your iCloud Apple ID and app-specific password (from
# appleid.apple.com > Sign-In and Security > App-Specific Passwords - NOT your Apple ID
# account password) and stores them in Windows Credential Manager for vault-calendar
# scripts to read silently.
#
# Run once per machine:
#   .\Set-CalDavCredential.ps1

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-credentials.ps1')

$Target = "vault-calendar:icloud"

$Cred = Get-Credential -Message "iCloud Apple ID and app-specific password (from appleid.apple.com)"
Set-StoredCredential -Target $Target -UserName $Cred.UserName -Password $Cred.Password

Write-Host "Stored credential for $($Cred.UserName) under Windows Credential Manager target '$Target'."
