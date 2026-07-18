# vault-credentials.unit-tests.ps1
# Direct unit tests for _shared/vault-credentials.ps1 (see Skill-Dev.md's Testing Shared
# Scripts section - shared scripts get their own tests here, not just incidental coverage
# via a consuming skill). Unlike skill-level unit tests, this does not use
# Initialize-TestWorktree/Reset-TestFolder - Credential Manager is real machine-global
# state, not a repo file, so there's no filesystem sandbox to isolate against. Isolation
# instead comes from a uniquely-named test Target that is always removed in a finally
# block, even on assertion failure.
# Usage: pwsh .claude/skills/_shared/tests/vault-credentials.unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' 'vault-test-common.ps1')
. (Join-Path $PSScriptRoot '..' 'vault-credentials.ps1')

# Local stand-in for Run-Test: reuses its pass/fail counters and output style, but skips
# Reset-TestFolder, which assumes file-based worktree isolation that doesn't apply to
# Credential Manager state.
function Invoke-CredTest {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    Write-Host "  $Name" -NoNewline
    try {
        $ok = & $Body
        if ($ok) {
            Write-Host '  PASS' -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host ''
            $script:failed++
        }
    } catch {
        Write-Host "`n  ERROR: $_" -ForegroundColor Red
        $script:failed++
    }
}

$TestTarget = "vault-calendar-unit-tests:$([Guid]::NewGuid())"

try {

Write-Host "`n-- Set-StoredCredential / Get-StoredCredential --"

Invoke-CredTest 'Round-trips username and password' {
    $sec = ConvertTo-SecureString "s3cret-p@ss" -AsPlainText -Force
    Set-StoredCredential -Target $TestTarget -UserName "someone@example.com" -Password $sec
    $result = Get-StoredCredential -Target $TestTarget
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($result.Password))
    ($result.UserName -eq "someone@example.com") -and ($plain -eq "s3cret-p@ss")
}

Invoke-CredTest 'Overwriting an existing target replaces the value, not appends' {
    $sec1 = ConvertTo-SecureString "first" -AsPlainText -Force
    $sec2 = ConvertTo-SecureString "second" -AsPlainText -Force
    Set-StoredCredential -Target $TestTarget -UserName "a@example.com" -Password $sec1
    Set-StoredCredential -Target $TestTarget -UserName "b@example.com" -Password $sec2
    $result = Get-StoredCredential -Target $TestTarget
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($result.Password))
    ($result.UserName -eq "b@example.com") -and ($plain -eq "second")
}

Invoke-CredTest 'Password with embedded unicode and special characters round-trips' {
    $sec = ConvertTo-SecureString "pässwörd!`"'#$%^&*()<>?" -AsPlainText -Force
    Set-StoredCredential -Target $TestTarget -UserName "u@example.com" -Password $sec
    $result = Get-StoredCredential -Target $TestTarget
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($result.Password))
    $plain -eq "pässwörd!`"'#$%^&*()<>?"
}

Write-Host "`n-- Get-StoredCredential (missing) --"

Invoke-CredTest 'Returns $null for a target that was never stored' {
    $null -eq (Get-StoredCredential -Target "vault-calendar-unit-tests:never-created-$([Guid]::NewGuid())")
}

Write-Host "`n-- Remove-StoredCredential --"

Invoke-CredTest 'Removes a stored credential; subsequent Get returns $null' {
    $sec = ConvertTo-SecureString "to-be-removed" -AsPlainText -Force
    Set-StoredCredential -Target $TestTarget -UserName "r@example.com" -Password $sec
    Remove-StoredCredential -Target $TestTarget
    $null -eq (Get-StoredCredential -Target $TestTarget)
}

Invoke-CredTest 'Removing a target that does not exist does not throw' {
    Remove-StoredCredential -Target "vault-calendar-unit-tests:already-gone-$([Guid]::NewGuid())"
    $true
}

} finally {
    Remove-StoredCredential -Target $TestTarget | Out-Null
}

Write-TestSummary
