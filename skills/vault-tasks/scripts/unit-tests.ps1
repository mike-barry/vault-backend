# unit-tests.ps1
# Test suite for init-tasks.ps1.
# Usage: pwsh .claude/skills/vault-tasks/scripts/unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')

$vaultRoot  = Get-VaultRoot $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'init-tasks.ps1'
$override   = '.vault-tasks-tests'

$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName $override
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot

function Invoke-Script {
    param(
        [string]$Path = ''
    )
    $argList = @()
    if ($Path) { $argList += '-Path'; $argList += $Path }

    $result = & pwsh -NonInteractive -NoProfile -File $scriptPath `
        -VaultRootOverride $testRoot `
        @argList *>&1
    return ($result | ForEach-Object { "$_" }) -join "`n"
}

try {

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

Write-Host "`n-- Validation --"

Run-Test 'Non-existent path exits with error' {
    $out = Invoke-Script -Path 'Projects\NoSuch'
    $out -match 'not found'
}

Run-Test 'Existing Tasks.md exits with error' {
    New-TestFile 'Projects\My-Project\Tasks.md' -Content '# My-Project Tasks'
    $out = Invoke-Script -Path 'Projects\My-Project'
    $out -match 'already exists'
}

# ---------------------------------------------------------------------------
# Creation
# ---------------------------------------------------------------------------

Write-Host "`n-- Creation --"

Run-Test 'Creates Tasks.md in the target folder' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' | Out-Null
    Assert-FileExists 'Projects\My-Project\Tasks.md'
}

Run-Test 'Tasks.md contains the correct H1' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' | Out-Null
    Assert-FileContains 'Projects\My-Project\Tasks.md' '# My-Project Tasks'
}

Run-Test 'Tasks.md has no scope field' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' | Out-Null
    Assert-FileNotContains 'Projects\My-Project\Tasks.md' 'scope:'
}

Run-Test 'Tasks.md contains all required sections' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' | Out-Null
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 🔔 Reminders') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 🔥 Current') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 🧱 Blocked') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 📋 Backlog') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 🗺️ Side Quests') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## ✅ Done')
}

Run-Test 'Tasks.md has no unresolved template tokens' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' | Out-Null
    Assert-FileNotContains 'Projects\My-Project\Tasks.md' '{{'
}

Run-Test 'Tasks.md written without BOM' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' | Out-Null
    Test-NoBom 'Projects\My-Project\Tasks.md'
}

Run-Test 'Works for an area path' {
    New-TestFile 'Areas\My-Area\.placeholder'
    Invoke-Script -Path 'Areas\My-Area' | Out-Null
    Assert-FileExists 'Areas\My-Area\Tasks.md'
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

Write-Host "`n-- Output --"

Run-Test 'Output mentions Tasks.md' {
    New-TestFile 'Projects\My-Project\.placeholder'
    $out = Invoke-Script -Path 'Projects\My-Project'
    Assert-OutputContains $out 'Tasks.md'
}

Run-Test 'Output mentions name' {
    New-TestFile 'Projects\My-Project\.placeholder'
    $out = Invoke-Script -Path 'Projects\My-Project'
    Assert-OutputContains $out 'My-Project'
}

} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
