# inject-provenance.ps1
# Writes doc.created/doc.archived/doc.type frontmatter into a file in place, ahead of the
# archive move, and strips any now-stale use_skill: agent.instructions entries. Uses the
# shared Get-FrontmatterField/Set-FrontmatterField helpers so writes match
# check-provenance.ps1's repair format exactly, instead of hand-editing YAML text.
#
# CreatedDate/ArchivedDate are taken as already-resolved values, not recomputed here - the
# caller (vault-doc-archive's Preview step) resolves them via recover-created-date.ps1 and
# today's date respectively, so Preview and Apply always agree on the same values. Type is
# likewise the caller's already-resolved Determine Type result.
#
# use_skill: entries route live edits through the owning skill; an archived doc is frozen
# and never rewritten, so the routing directive is stale the moment the file lands in
# Archive/. Removed via the shared Remove-UseSkillAgentInstructions - bare and pinned:
# entries are left untouched.
#
# Usage:
#   pwsh -NoProfile -File inject-provenance.ps1 -SourcePath <vault-relative-source-path> `
#       -CreatedDate <YYYY-MM-DD> -ArchivedDate <YYYY-MM-DD> -Type <Type>

param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$CreatedDate,
    [Parameter(Mandatory)][string]$ArchivedDate,
    # The type resolved by the Determine Type step. Written only if doc.type is not already
    # present - a file arriving at vault-doc-archive may already carry a doc.type from its
    # scaffolding skill, and that value is authoritative, not this flow's inference.
    [Parameter(Mandatory)][string]$Type,
    # Override the vault root; used by unit tests to redirect to a temporary worktree.
    [string]$VaultRootOverride
)

$ErrorActionPreference = 'Stop'

$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-frontmatter.ps1')

$vaultRoot = if ($VaultRootOverride) { $VaultRootOverride.TrimEnd('\', '/') + '\' } else { Get-VaultRoot -StartPath $PSScriptRoot }

$abs = Resolve-VaultPath -VaultRoot $vaultRoot -Path $SourcePath
if (-not (Test-Path -LiteralPath $abs)) {
    Write-Error "Source file not found: $SourcePath"
    exit 1
}

$content = [System.IO.File]::ReadAllText($abs, [System.Text.Encoding]::UTF8)

# doc.created: added only if not already present - never overwrite an existing capture date.
if (-not (Get-FrontmatterField -Content $content -Field 'doc.created')) {
    $content = Set-FrontmatterField -Content $content -Field 'doc.created' -Value $CreatedDate
}
# doc.archived: always written - represents this archive event.
$content = Set-FrontmatterField -Content $content -Field 'doc.archived' -Value $ArchivedDate

# doc.type: added only if not already present - never override a value the scaffolding skill
# (or a prior manual edit) already wrote.
if (-not (Get-FrontmatterField -Content $content -Field 'doc.type')) {
    $content = Set-FrontmatterField -Content $content -Field 'doc.type' -Value $Type
}

$content = Remove-UseSkillAgentInstructions -Content $content

[System.IO.File]::WriteAllText($abs, $content, $Utf8NoBom)
Write-Host "Injected frontmatter: $SourcePath"
