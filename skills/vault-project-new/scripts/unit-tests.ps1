# unit-tests.ps1
# Test suite for new-vault-item.ps1.
# Usage: pwsh .claude/skills/vault-project-new/scripts/unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')

$vaultRoot  = Get-VaultRoot $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'new-vault-item.ps1'
$override   = '.vault-new-tests'

$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName $override
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot

function Invoke-Script {
    param(
        [string]$Name        = '',
        [string]$Type        = '',
        [string]$Description = '',
        [string]$GoalOrScope = ''
    )
    $argList = @()
    if ($Name)        { $argList += '-Name';        $argList += $Name }
    if ($Type)        { $argList += '-Type';        $argList += $Type }
    if ($Description) { $argList += '-Description'; $argList += $Description }
    if ($GoalOrScope) { $argList += '-GoalOrScope'; $argList += $GoalOrScope }

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

Run-Test 'Bad name format exits with error' {
    $out = Invoke-Script -Name 'bad name' -Type 'project' -Description 'desc' -Goal 'some goal'
    $out -match 'Title-Case'
}

Run-Test 'lowercase-leading name exits with error' {
    $out = Invoke-Script -Name 'myProject' -Type 'project' -Description 'desc' -Goal 'some goal'
    $out -match 'Title-Case'
}

Run-Test 'Missing GoalOrScope exits with error' {
    $out = Invoke-Script -Name 'My-Project' -Type 'project' -Description 'desc'
    $out -match 'GoalOrScope'
}

Run-Test 'Duplicate folder exits with error' {
    Invoke-Script -Name 'Dupe' -Type 'project' -Description 'first' -GoalOrScope 'do a thing' | Out-Null
    $out = Invoke-Script -Name 'Dupe' -Type 'project' -Description 'second' -GoalOrScope 'do a thing'
    $out -match 'already exists'
}

# ---------------------------------------------------------------------------
# Project creation
# ---------------------------------------------------------------------------

Write-Host "`n-- Project creation --"

Run-Test 'Creates project folder under Projects/' {
    Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Ship it' | Out-Null
    Assert-FileExists 'Projects\My-Project'
}

Run-Test 'Creates Inbox, Corpus, Archive subfolders' {
    Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Ship it' | Out-Null
    (Assert-FileExists 'Projects\My-Project\Inbox') -and
    (Assert-FileExists 'Projects\My-Project\Corpus') -and
    (Assert-FileExists 'Projects\My-Project\Archive')
}

Run-Test 'Creates .placeholder in each subfolder' {
    Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Ship it' | Out-Null
    (Assert-FileExists 'Projects\My-Project\Inbox\.placeholder') -and
    (Assert-FileExists 'Projects\My-Project\Corpus\.placeholder') -and
    (Assert-FileExists 'Projects\My-Project\Archive\.placeholder')
}

Run-Test 'Creates folder note at <Name>.md' {
    Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Ship it' | Out-Null
    Assert-FileExists 'Projects\My-Project\My-Project.md'
}

Run-Test 'Folder note contains Name and Description' {
    Invoke-Script -Name 'Cool-Thing' -Type 'project' -Description 'Does cool things' -GoalOrScope 'Ship it' | Out-Null
    (Assert-FileContains 'Projects\Cool-Thing\Cool-Thing.md' 'Cool-Thing') -and
    (Assert-FileContains 'Projects\Cool-Thing\Cool-Thing.md' 'Does cool things')
}

Run-Test 'Project folder note contains ## Goal with goal text' {
    Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Finish by Q3' | Out-Null
    (Assert-FileContains 'Projects\My-Project\My-Project.md' '## Goal') -and
    (Assert-FileContains 'Projects\My-Project\My-Project.md' 'Finish by Q3')
}

Run-Test 'Project folder note does not contain ## Scope' {
    Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Ship it' | Out-Null
    Assert-FileNotContains 'Projects\My-Project\My-Project.md' '## Scope'
}

Run-Test 'Folder note has no unresolved template tokens' {
    Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Ship it' | Out-Null
    Assert-FileNotContains 'Projects\My-Project\My-Project.md' '{{'
}

Run-Test 'Folder note written without BOM' {
    Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Ship it' | Out-Null
    Test-NoBom 'Projects\My-Project\My-Project.md'
}

Run-Test 'Does not create Tasks.md (owned by vault-tasks)' {
    Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Ship it' | Out-Null
    Assert-FileNotExists 'Projects\My-Project\Tasks.md'
}

# ---------------------------------------------------------------------------
# Area creation
# ---------------------------------------------------------------------------

Write-Host "`n-- Area creation --"

Run-Test 'Creates area folder under Areas/<Name>/' {
    Invoke-Script -Name 'My-Area' -Type 'area' -Description 'An area' -GoalOrScope 'Covers biking' | Out-Null
    Assert-FileExists 'Areas\My-Area'
}

Run-Test 'Creates subfolders and placeholders for area' {
    Invoke-Script -Name 'My-Area' -Type 'area' -Description 'An area' -GoalOrScope 'Covers biking' | Out-Null
    (Assert-FileExists 'Areas\My-Area\Inbox\.placeholder') -and
    (Assert-FileExists 'Areas\My-Area\Corpus\.placeholder') -and
    (Assert-FileExists 'Areas\My-Area\Archive\.placeholder')
}

Run-Test 'Area folder note contains ## Scope with scope text' {
    Invoke-Script -Name 'My-Area' -Type 'area' -Description 'An area' -GoalOrScope 'Covers biking and trails' | Out-Null
    (Assert-FileContains 'Areas\My-Area\My-Area.md' '## Scope') -and
    (Assert-FileContains 'Areas\My-Area\My-Area.md' 'Covers biking and trails')
}

Run-Test 'Area folder note does not contain ## Goal' {
    Invoke-Script -Name 'My-Area' -Type 'area' -Description 'An area' -GoalOrScope 'Covers biking' | Out-Null
    Assert-FileNotContains 'Areas\My-Area\My-Area.md' '## Goal'
}

Run-Test 'Area folder note has no unresolved template tokens' {
    Invoke-Script -Name 'My-Area' -Type 'area' -Description 'An area' -GoalOrScope 'Covers biking' | Out-Null
    Assert-FileNotContains 'Areas\My-Area\My-Area.md' '{{'
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

Write-Host "`n-- Output --"

Run-Test 'Output mentions next steps (vault-tasks, vault-agent-frontmatter)' {
    $out = Invoke-Script -Name 'My-Project' -Type 'project' -Description 'A project' -GoalOrScope 'Ship it'
    (Assert-OutputContains $out 'vault-tasks') -and
    (Assert-OutputContains $out 'vault-agent-frontmatter')
}

Run-Test 'Single-word Title-Case name is accepted' {
    $out = Invoke-Script -Name 'Maui' -Type 'project' -Description 'A trip' -GoalOrScope 'Go to Maui'
    -not ($out -match 'Title-Case')
}

} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
