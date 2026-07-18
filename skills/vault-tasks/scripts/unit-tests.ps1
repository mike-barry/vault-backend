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
        [string]$Path  = '',
        [string]$Scope = ''
    )
    $argList = @()
    if ($Path)  { $argList += '-Path';  $argList += $Path }
    if ($Scope) { $argList += '-Scope'; $argList += $Scope }

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

Run-Test 'Missing Scope exits with error' {
    New-TestFile 'Projects\My-Project\.placeholder'
    $out = Invoke-Script -Path 'Projects\My-Project'
    $out -match 'Scope'
}

Run-Test 'Invalid Scope value exits with error' {
    New-TestFile 'Projects\My-Project\.placeholder'
    $out = Invoke-Script -Path 'Projects\My-Project' -Scope 'invalid'
    $out -match 'Scope'
}

Run-Test 'Non-existent path exits with error' {
    $out = Invoke-Script -Path 'Projects\NoSuch' -Scope 'personal'
    $out -match 'not found'
}

Run-Test 'Existing Tasks.md exits with error' {
    New-TestFile 'Projects\My-Project\Tasks.md' -Content '# My-Project Tasks'
    $out = Invoke-Script -Path 'Projects\My-Project' -Scope 'personal'
    $out -match 'already exists'
}

# ---------------------------------------------------------------------------
# Creation
# ---------------------------------------------------------------------------

Write-Host "`n-- Creation --"

Run-Test 'Creates Tasks.md in the target folder' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' -Scope 'personal' | Out-Null
    Assert-FileExists 'Projects\My-Project\Tasks.md'
}

Run-Test 'Tasks.md contains the correct H1' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' -Scope 'personal' | Out-Null
    Assert-FileContains 'Projects\My-Project\Tasks.md' '# My-Project Tasks'
}

Run-Test 'Tasks.md contains scope: personal in frontmatter' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' -Scope 'personal' | Out-Null
    Assert-FileContains 'Projects\My-Project\Tasks.md' 'scope: personal'
}

Run-Test 'Tasks.md contains scope: work in frontmatter' {
    New-TestFile 'Projects\Work-Thing\.placeholder'
    Invoke-Script -Path 'Projects\Work-Thing' -Scope 'work' | Out-Null
    Assert-FileContains 'Projects\Work-Thing\Tasks.md' 'scope: work'
}

Run-Test 'Tasks.md contains all required sections' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' -Scope 'personal' | Out-Null
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 🔔 Reminders') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 🔥 Active') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 🧱 Blocked') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 📋 Backlog') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## 🗺️ Side Quests') -and
    (Assert-FileContains 'Projects\My-Project\Tasks.md' '## ✅ Done')
}

Run-Test 'Tasks.md has no unresolved template tokens' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' -Scope 'personal' | Out-Null
    Assert-FileNotContains 'Projects\My-Project\Tasks.md' '{{'
}

Run-Test 'Tasks.md written without BOM' {
    New-TestFile 'Projects\My-Project\.placeholder'
    Invoke-Script -Path 'Projects\My-Project' -Scope 'personal' | Out-Null
    Test-NoBom 'Projects\My-Project\Tasks.md'
}

Run-Test 'Works for an area path' {
    New-TestFile 'Areas\My-Area\.placeholder'
    Invoke-Script -Path 'Areas\My-Area' -Scope 'personal' | Out-Null
    Assert-FileExists 'Areas\My-Area\Tasks.md'
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

Write-Host "`n-- Output --"

Run-Test 'Output mentions Tasks.md' {
    New-TestFile 'Projects\My-Project\.placeholder'
    $out = Invoke-Script -Path 'Projects\My-Project' -Scope 'personal'
    Assert-OutputContains $out 'Tasks.md'
}

Run-Test 'Output mentions name and scope' {
    New-TestFile 'Projects\My-Project\.placeholder'
    $out = Invoke-Script -Path 'Projects\My-Project' -Scope 'personal'
    (Assert-OutputContains $out 'My-Project') -and
    (Assert-OutputContains $out 'personal')
}

} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
