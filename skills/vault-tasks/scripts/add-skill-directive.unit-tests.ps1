# Unit tests for add-skill-directive.ps1.
# Run: pwsh .claude/skills/vault-tasks/scripts/add-skill-directive.unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$_skillDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $_skillDir '..' '_shared' 'vault-common.ps1')
. (Join-Path $_skillDir '..' '_shared' 'vault-test-common.ps1')

$vaultRoot = Get-VaultRoot $PSScriptRoot
$override  = '.vt-test-tmp'

$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName $override
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot

function Invoke-AddDirective {
    param([string]$RelPath, [string]$When, [string]$Note)
    $scriptPath = Join-Path $PSScriptRoot 'add-skill-directive.ps1'
    $docPath = Join-Path $testRoot $RelPath
    $a = @('-NoProfile', '-File', $scriptPath, '-DocPath', $docPath, '-When', $When, '-VaultRootOverride', $worktreePath)
    if ($Note) { $a += @('-Note', $Note) }
    (& pwsh @a 2>&1 | Out-String)
}

try {
    Write-Host "`nadd-skill-directive.ps1"
    Reset-TestFolder
    New-TestFile 'Tasks.md' "# Example Tasks`n`n## 🔔 Reminders`n"
    $out = Invoke-AddDirective -RelPath 'Tasks.md' -When 'editing this file' -Note 'Do not hand-edit task entries.'
    Assert-That 'reports the directive was added' ($out -match 'Added vault-tasks skill directive') $out
    Assert-That 'writes agent.instructions with use_skill: vault-tasks' (
        (Get-TestFileContent 'Tasks.md') -match "use_skill: `"vault-tasks`"" -and
        (Get-TestFileContent 'Tasks.md') -match "when: `"editing this file`"" -and
        (Get-TestFileContent 'Tasks.md') -match "note: `"Do not hand-edit task entries\.`""
    )
    Assert-That 'preserves the body' ((Get-TestFileContent 'Tasks.md') -match '## 🔔 Reminders')

    $out2 = Invoke-AddDirective -RelPath 'Tasks.md' -When 'editing this file' -Note 'Do not hand-edit task entries.'
    Assert-That 're-running is a no-op' ($out2 -match 'already present') $out2

    Reset-TestFolder
    New-TestFile 'Tasks.md' "---`nagent.skill_instructions:`n  - `"Modify this file only via the vault-tasks skill.`"`n---`n# Example Tasks`n"
    Invoke-AddDirective -RelPath 'Tasks.md' -When 'editing this file' -Note 'Do not hand-edit task entries.' | Out-Null
    Assert-That 'strips the legacy agent.skill_instructions block' ((Get-TestFileContent 'Tasks.md') -notmatch 'agent\.skill_instructions')
    Assert-That 'writes the new agent.instructions block' ((Get-TestFileContent 'Tasks.md') -match "use_skill: `"vault-tasks`"")
} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
