# Unit tests for add-skill-directive.ps1.
# Run: pwsh .claude/skills/vault-docs/scripts/unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$_skillDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $_skillDir '..' '_shared' 'vault-common.ps1')
. (Join-Path $_skillDir '..' '_shared' 'vault-test-common.ps1')

$vaultRoot = Get-VaultRoot $PSScriptRoot
$override  = '.vd-test-tmp'

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
    New-TestFile 'Plan-Example.md' "# Example Plan`n`nBody text.`n"
    $out = Invoke-AddDirective -RelPath 'Plan-Example.md' -When 'editing this file or acting on its checklist'
    Assert-That 'reports the directive was added' ($out -match 'Added vault-docs skill directive') $out
    Assert-That 'writes agent.instructions with use_skill: vault-docs' (
        (Get-TestFileContent 'Plan-Example.md') -match "use_skill: `"vault-docs`"" -and
        (Get-TestFileContent 'Plan-Example.md') -match "when: `"editing this file or acting on its checklist`""
    )
    Assert-That 'preserves the body' ((Get-TestFileContent 'Plan-Example.md') -match 'Body text\.')

    $out2 = Invoke-AddDirective -RelPath 'Plan-Example.md' -When 'editing this file or acting on its checklist'
    Assert-That 're-running is a no-op' ($out2 -match 'already present') $out2

    Reset-TestFolder
    New-TestFile 'Tasks.md' "# Tasks`n"
    Invoke-AddDirective -RelPath 'Tasks.md' -When 'editing this file' -Note 'Do not hand-edit task entries.' | Out-Null
    Assert-That 'writes an optional note field' ((Get-TestFileContent 'Tasks.md') -match "note: `"Do not hand-edit task entries\.`"")
} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
