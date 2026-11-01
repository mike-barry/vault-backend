# unit-tests.ps1
# Test suite for resolve-vault.ps1.
# Usage: pwsh .claude/skills/vault-doc-rename/scripts/unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')

$vaultRoot  = Get-VaultRoot $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'resolve-vault.ps1'
$override   = '.vault-doc-rename-tests'

$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName $override
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot

# Write a CLI install under testRoot: bin\vault.settings.json pointing at config\vaults.json, which
# registers the given vaults ({ name = path }) with $Default as the default.
function New-Registry {
    param(
        [hashtable]$Vaults,
        [string]$Default = 'primary',
        [string]$VaultsConfigPath = '../config/vaults.json'
    )
    $entries = @{}
    foreach ($k in $Vaults.Keys) { $entries[$k] = @{ path = $Vaults[$k] } }
    New-TestFile 'config\vaults.json' (@{ default_vault = $Default; vaults = $entries } | ConvertTo-Json -Depth 4)
    $settings = "{`n  // The CLI's own configuration.`n  `"VaultsConfigPath`": `"$VaultsConfigPath`"`n}"
    New-TestFile 'bin\vault.settings.json' $settings
}

# Run the script for the given repo root against the test install; returns { Exit, Output }.
function Invoke-Script {
    param([string]$Root)
    $result = & pwsh -NonInteractive -NoProfile -File $scriptPath `
        -VaultRootOverride $Root `
        -SettingsPath (Join-Path $testRoot 'bin\vault.settings.json') *>&1
    [pscustomobject]@{ Exit = $LASTEXITCODE; Output = ($result | ForEach-Object { "$_" }) -join "`n" }
}

try {

$cloneA = Join-Path $testRoot 'clone-a'
$cloneB = Join-Path $testRoot 'clone-b'

Write-Host "`nresolve-vault"

Run-Test 'names the default vault for its own path' {
    New-Registry @{ primary = $cloneA; other = $cloneB }
    $r = Invoke-Script $cloneA
    $j = $r.Output | ConvertFrom-Json
    ($r.Exit -eq 0) -and ($j.Vault -eq 'primary') -and $j.Default
}

Run-Test 'names a non-default vault and reports it is not the default' {
    New-Registry @{ primary = $cloneA; other = $cloneB }
    $r = Invoke-Script $cloneB
    $j = $r.Output | ConvertFrom-Json
    ($r.Exit -eq 0) -and ($j.Vault -eq 'other') -and (-not $j.Default)
}

Run-Test 'matches across separator style, case, and trailing separator' {
    New-Registry @{ primary = ($cloneA.Replace('\', '/').ToUpper() + '/') }
    $r = Invoke-Script $cloneA
    ($r.Exit -eq 0) -and (($r.Output | ConvertFrom-Json).Vault -eq 'primary')
}

Run-Test 'refuses a repo no registered vault points at' {
    New-Registry @{ primary = $cloneA }
    $r = Invoke-Script $cloneB
    ($r.Exit -eq 1) -and (Assert-OutputContains $r.Output 'No vault in')
}

Run-Test 'refuses when the registry file is missing' {
    New-Registry @{ primary = $cloneA } -VaultsConfigPath '../config/missing.json'
    $r = Invoke-Script $cloneA
    ($r.Exit -eq 1) -and (Assert-OutputContains $r.Output 'Vault registry not found')
}

} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
