# recover-created-date.ps1
# Recovers the doc.created date for a file about to be archived, via the shared Get-CreatedDate
# chain: existing 'doc.created' frontmatter -> filename date segment -> git first-commit date.
# Prints the recovered date, or nothing if none of those resolve.
#
# The interactive archive flow's "today" last-resort fallback (see vault-doc-archive/SKILL.md
# "Recover Creation Date") is deliberately NOT part of this script - the shared chain must
# never guess (it is also relied on by the vault-lint provenance check, which needs to flag
# unresolved dates for manual review rather than silently defaulting). Applying "today" is
# agent-level policy layered on top of this script's output.
#
# Usage:
#   pwsh -NoProfile -File recover-created-date.ps1 -SourcePath <vault-relative-source-path>

param(
    [Parameter(Mandatory)][string]$SourcePath,
    # Override the vault root; used by unit tests to redirect to a temporary worktree.
    [string]$VaultRootOverride
)

$ErrorActionPreference = 'Stop'

$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-frontmatter.ps1')

$vaultRoot = if ($VaultRootOverride) { Format-VaultRoot $VaultRootOverride } else { Get-VaultRoot -StartPath $PSScriptRoot }

$abs = Resolve-VaultPath -VaultRoot $vaultRoot -Path $SourcePath
if (-not (Test-Path -LiteralPath $abs)) {
    Write-Error "Source file not found: $SourcePath"
    exit 1
}

$content = [System.IO.File]::ReadAllText($abs, [System.Text.Encoding]::UTF8)
$rel     = $abs.Substring($vaultRoot.Length)

$recovered = Get-CreatedDate -VaultRoot $vaultRoot -RelPath $rel -Content $content
if ($recovered) { Write-Output $recovered }
