# add-skill-directive.ps1
# Thin CLI entry point over the shared Add-AgentInstructionEntry function
# (_shared/vault-frontmatter.ps1), fixed to vault-tasks' own skill-owned-file directive
# (UseSkill: 'vault-tasks'). init-tasks.ps1's template and any migration pass call this
# directly by path - no Skill-tool invocation of vault-agent-frontmatter needed just to
# inject the fixed 3-4 line directive.
# Also strips a legacy 'agent.skill_instructions:' block, if present, so migrating an
# existing Tasks.md is a single call rather than a separate cleanup step.
# Idempotent - safe to call unconditionally, even if the entry may already be present.
#
# Usage:
#   pwsh .claude/skills/vault-tasks/scripts/add-skill-directive.ps1 `
#     -DocPath <path> -When 'editing this file' [-Note '...']
param(
    # Path to the doc to update - vault-relative or absolute.
    [Parameter(Mandatory)][string]$DocPath,
    # Bare condition per the schema's field conventions (e.g. 'editing this file').
    [Parameter(Mandatory)][string]$When,
    # Optional doc-type-specific detail that doesn't fit the When condition.
    [string]$Note,
    # Vault root directory. Auto-resolved when not specified; pass explicitly for a test worktree.
    [string]$VaultRootOverride
)

$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-frontmatter.ps1')

$resolvedPath = if ([System.IO.Path]::IsPathRooted($DocPath)) {
    $DocPath
} else {
    $vaultRoot = if ($VaultRootOverride) { $VaultRootOverride } else { Get-VaultRoot $PSScriptRoot }
    Join-Path $vaultRoot $DocPath
}

$content = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
$stripped = Remove-FrontmatterBlock -Content $content -Field 'agent.skill_instructions'

$addArgs = @{ Content = $stripped; Type = 'UseSkill'; UseSkill = 'vault-tasks'; When = $When }
if ($Note) { $addArgs.Note = $Note }
$updated = Add-AgentInstructionEntry @addArgs

if ($updated -ne $content) {
    [System.IO.File]::WriteAllText($resolvedPath, $updated, $Utf8NoBom)
    Write-Host "Added vault-tasks skill directive to $DocPath"
} else {
    Write-Host "vault-tasks skill directive already present in $DocPath (no-op)"
}
