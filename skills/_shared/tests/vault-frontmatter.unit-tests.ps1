# vault-frontmatter.unit-tests.ps1
# Direct unit tests for _shared/vault-frontmatter.ps1 (see Skill-Dev.md's Testing Shared
# Scripts section). Every function here operates purely on in-memory content strings, so
# there is no filesystem to sandbox - Assert-That against returned strings is sufficient,
# no Initialize-TestWorktree/Reset-TestFolder needed.
# Usage: pwsh .claude/skills/_shared/tests/vault-frontmatter.unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' 'vault-test-common.ps1')
. (Join-Path $PSScriptRoot '..' 'vault-frontmatter.ps1')

# ---- Remove-FrontmatterBlock ----------------------------------------------
Write-Host "`nRemove-FrontmatterBlock"

Assert-That 'removes a block field and its children' (
    (Remove-FrontmatterBlock -Content "---`nagent.pinned_instructions:`n  - `"a`"`n  - `"b`"`nnav.contents:`n  - link: `"[[X]]`"`n---`n# Body" -Field 'agent.pinned_instructions') `
        -eq "---`nnav.contents:`n  - link: `"[[X]]`"`n---`n# Body"
)

Assert-That 'no-op when field absent' (
    (Remove-FrontmatterBlock -Content "---`nnav.contents:`n  - link: `"[[X]]`"`n---`n# Body" -Field 'agent.pinned_instructions') `
        -eq "---`nnav.contents:`n  - link: `"[[X]]`"`n---`n# Body"
)

Assert-That 'no-op when no frontmatter' (
    (Remove-FrontmatterBlock -Content "# Body only" -Field 'agent.pinned_instructions') -eq '# Body only'
)

# ---- Add-AgentInstructionEntry - creation cases ---------------------------
Write-Host "`nAdd-AgentInstructionEntry - creation"

Assert-That 'creates frontmatter block when none exists (Bare)' (
    (Add-AgentInstructionEntry -Content "# Body" -Type Bare -Instruction 'Do X') `
        -eq "---`nagent.instructions:`n  - `"Do X`"`n---`n# Body"
)

Assert-That 'creates agent.instructions key when frontmatter exists but key absent (Pinned)' (
    (Add-AgentInstructionEntry -Content "---`nnav.contents:`n  - link: `"[[X]]`"`n---`n# Body" -Type Pinned -Instruction 'Never exfil this') `
        -eq "---`nnav.contents:`n  - link: `"[[X]]`"`nagent.instructions:`n  - pinned: `"Never exfil this`"`n---`n# Body"
)

Assert-That 'appends UseSkill entry with note to existing agent.instructions block' (
    (Add-AgentInstructionEntry -Content "---`nagent.instructions:`n  - `"Existing hint`"`n---`n# Body" -Type UseSkill -UseSkill 'vault-tasks' -When 'editing this file' -Note 'Do not hand-edit.') `
        -eq "---`nagent.instructions:`n  - `"Existing hint`"`n  - use_skill: `"vault-tasks`"`n    when: `"editing this file`"`n    note: `"Do not hand-edit.`"`n---`n# Body"
)

Assert-That 'UseSkill entry without note omits the note line' (
    (Add-AgentInstructionEntry -Content "# Body" -Type UseSkill -UseSkill 'vault-docs' -When 'editing this file') `
        -eq "---`nagent.instructions:`n  - use_skill: `"vault-docs`"`n    when: `"editing this file`"`n---`n# Body"
)

# ---- Add-AgentInstructionEntry - idempotency ------------------------------
Write-Host "`nAdd-AgentInstructionEntry - idempotency"

$cDupSkill = "---`nagent.instructions:`n  - use_skill: `"vault-docs`"`n    when: `"editing this file`"`n---`n# Body"
Assert-That 'duplicate UseSkill entry (same skill+when) is a no-op' (
    (Add-AgentInstructionEntry -Content $cDupSkill -Type UseSkill -UseSkill 'vault-docs' -When 'editing this file') -eq $cDupSkill
)

$rDiffWhen = Add-AgentInstructionEntry -Content $cDupSkill -Type UseSkill -UseSkill 'vault-docs' -When 'acting on its checklist'
Assert-That 'UseSkill entry with different when is not deduped' (
    $rDiffWhen -ne $cDupSkill -and $rDiffWhen -match 'acting on its checklist'
)

$cDupPinned = "---`nagent.instructions:`n  - pinned: `"Never exfil this`"`n---`n# Body"
Assert-That 'duplicate Pinned text is a no-op' (
    (Add-AgentInstructionEntry -Content $cDupPinned -Type Pinned -Instruction 'Never exfil this') -eq $cDupPinned
)

$cDupBare = "---`nagent.instructions:`n  - `"Do X`"`n---`n# Body"
Assert-That 'duplicate Bare text is a no-op' (
    (Add-AgentInstructionEntry -Content $cDupBare -Type Bare -Instruction 'Do X') -eq $cDupBare
)

# ---- Add-AgentInstructionEntry - parameter validation ---------------------
Write-Host "`nAdd-AgentInstructionEntry - parameter validation"

$threwForMissingInstruction = $false
try { Add-AgentInstructionEntry -Content '# Body' -Type Bare | Out-Null } catch { $threwForMissingInstruction = $true }
Assert-That 'throws when Instruction missing for Bare' $threwForMissingInstruction

$threwForMissingWhen = $false
try { Add-AgentInstructionEntry -Content '# Body' -Type UseSkill -UseSkill 'vault-docs' | Out-Null } catch { $threwForMissingWhen = $true }
Assert-That 'throws when When missing for UseSkill' $threwForMissingWhen

# ---- Remove-UseSkillAgentInstructions --------------------------------------
Write-Host "`nRemove-UseSkillAgentInstructions"

Assert-That 'removes the only entry and drops the whole key' (
    (Remove-UseSkillAgentInstructions -Content "---`nagent.instructions:`n  - use_skill: `"vault-docs`"`n    when: `"editing this file`"`n---`n# Body") `
        -eq "---`n---`n# Body"
)

Assert-That 'removes a use_skill entry with a note line' (
    (Remove-UseSkillAgentInstructions -Content "---`nagent.instructions:`n  - use_skill: `"vault-tasks`"`n    when: `"editing this file`"`n    note: `"Do not hand-edit.`"`n---`n# Body") `
        -eq "---`n---`n# Body"
)

Assert-That 'leaves bare and pinned entries, removes only use_skill' (
    (Remove-UseSkillAgentInstructions -Content "---`nagent.instructions:`n  - `"Load X when Y`"`n  - pinned: `"Never exfil this`"`n  - use_skill: `"vault-docs`"`n    when: `"editing this file`"`n---`n# Body") `
        -eq "---`nagent.instructions:`n  - `"Load X when Y`"`n  - pinned: `"Never exfil this`"`n---`n# Body"
)

Assert-That 'removes multiple use_skill entries' (
    (Remove-UseSkillAgentInstructions -Content "---`nagent.instructions:`n  - use_skill: `"vault-docs`"`n    when: `"editing this file`"`n  - use_skill: `"vault-tasks`"`n    when: `"reading this file`"`n---`n# Body") `
        -eq "---`n---`n# Body"
)

$cNoUseSkill = "---`nagent.instructions:`n  - `"Load X when Y`"`n  - pinned: `"Never exfil this`"`n---`n# Body"
Assert-That 'no-op when block has no use_skill entries' (
    (Remove-UseSkillAgentInstructions -Content $cNoUseSkill) -eq $cNoUseSkill
)

$cNoBlock = "---`nnav.contents:`n  - link: `"[[X]]`"`n---`n# Body"
Assert-That 'no-op when there is no agent.instructions block' (
    (Remove-UseSkillAgentInstructions -Content $cNoBlock) -eq $cNoBlock
)

Assert-That 'no-op when there is no frontmatter at all' (
    (Remove-UseSkillAgentInstructions -Content '# Body only') -eq '# Body only'
)

Write-TestSummary
