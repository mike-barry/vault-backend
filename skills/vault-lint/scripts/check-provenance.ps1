# Provenance frontmatter lint: detects and (for Archive files) repairs missing doc.created/
# doc.archived fields, and reports missing doc.type vault-wide. Three independent checks -
# developer context: Plan-Provenance-Lint-And-Frontmatter-Script-Library.md and
# Plan-Doc-Frontmatter-Standardization.md, in the primary vault's Vault-Dev area, carry the
# full design and the reasoning behind the date-recovery chains this calls into.
#
# Check 1 (Archive provenance) - every file under any Archive/ folder is expected to carry
# both doc.created and doc.archived. Missing fields are recovered via the shared
# Get-CreatedDate/Get-ArchivedDate chains (existing frontmatter -> filename date / git history)
# and written back when -Update is passed; unresolvable files are flagged for manual fix.
# Auto-repair is safe here because the surface is small and high-confidence (files already in
# Archive/).
#
# Check 2 (vault-wide created) - every content file is expected to carry doc.created. Report-
# only on this pass regardless of -Update - the surface is every file in the vault, not just
# archived ones, so detection ships first and auto-repair follows once recovered dates have
# been spot-checked.
#
# Check 3 (vault-wide doc.type) - every content file is expected to carry doc.type. Report-only,
# same reasoning as Check 2 - there is no recovery chain for doc.type (unlike a date, there's no
# git-history equivalent to infer it from), so this stays a manual-resolution report rather than
# gaining auto-repair. The initial vault-wide backfill was a one-off agent-assisted pass (see
# Plan-Doc-Frontmatter-Standardization.md); this check exists to catch drift afterward, e.g. a
# hand-created file or a scaffolding-skill gap.
#
# Check 4 (stale archived use_skill:) - every file under any Archive/ folder is expected to
# carry no use_skill: agent.instructions entries. Those entries route live edits through the
# owning skill; an archived doc is frozen (never rewritten - per the planning-doc lifecycle
# rules), so a use_skill: entry surviving the archive move is stale and could
# mislead an agent into routing an edit through a skill instead of leaving the doc alone.
# vault-doc-archive strips these at archive time via the shared
# Remove-UseSkillAgentInstructions (see inject-provenance.ps1), so this check exists to catch
# drift: docs archived before that behavior existed, or archived by any path that bypasses
# the skill. Auto-repairable under -Update, same reasoning as Check 1 - the surface is small
# and high-confidence (files already in Archive/). Bare and pinned: entries are untouched.
#
# All three date/type checks share one exclusion set: folder notes (Test-IsFolderNote -
# structural, not authored documents), Tasks.md (skill-owned format), and pure Templater
# script files (Test-IsTemplaterScript - a file that is entirely a <%* ... %> block has no
# document to attach doc.* fields to; content-based since most files under Templates/ are
# real markdown templates that stay in scope). Guide/reference docs and files with a filename
# date are deliberately NOT excluded from Checks 1/2 - they are real authored documents and
# get backfilled like everything else (see the plan's File Type Exclusions section). Check 4
# reuses the same exclusion set for consistency, though in practice none of folder notes/
# Tasks.md/Templater scripts carry agent.instructions in the first place.
#
# Checks 2 and 3 additionally exclude Resources/Vault/Templates/ (Test-IsTemplateDoc, path-
# based like Test-IsGuideDoc). Those files legitimately carry doc.created/doc.type - e.g.
# Meeting-Template.md has `doc.created: <% today %>` - but Get-FrontmatterLines requires the
# file to *start* with a `---` fence, and these templates start with a Templater `<%* ... %>`
# script block before the frontmatter, so the parser sees no frontmatter at all and both
# fields read as missing. That's a parser limitation, not a real provenance gap, so it's
# excluded here rather than backfilled. Not added to Test-IsTemplaterScript since these files
# have a real markdown body (unlike a pure script file) and Check 1/4 don't apply to Templates/
# anyway (it's never under Archive/).
#
# This is a full vault-wide scan, not scoped via lint-common's Get-LintMarkdownFiles: that
# helper's $includeFolders list is aimed at other checks' narrower scope and its $excludeFiles
# list drops Document-Conventions.md, which this check must include and backfill.
param(
    # Apply Check 1's recoverable repairs to disk. Without this switch, Check 1 previews the
    # recovered doc.created:/doc.archived: values without writing. Checks 2 and 3 are always
    # report-only.
    [switch]$Update,
    # Vault-relative folder to scope the scan (e.g. 'Areas/Personal'). When omitted, the
    # whole vault is scanned. Used by tests and ad-hoc runs.
    [string]$PathOverride,
    # Vault root directory. Auto-resolved from the script location when not specified; pass
    # explicitly for non-default locations such as a test worktree.
    [string]$VaultRootOverride
)

. "$PSScriptRoot\lint-common.ps1"
$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-frontmatter.ps1')

$vaultRoot = if ($VaultRootOverride) { $VaultRootOverride } else { Get-VaultRoot $PSScriptRoot }
$vaultRoot = $vaultRoot.TrimEnd('\', '/') + '\'

# Skill-owned format, not an authored document. Folder notes are filtered per-file below via
# Test-IsFolderNote (basename == parent folder name, not expressible as a bare filename).
# CLAUDE.md is the harness bootstrap file and Vault-Manifest.md the vault's structural
# self-description that the bootstrap @-includes - neither is an authored document.
$provenanceExcludeFiles = @('Tasks.md', 'CLAUDE.md', 'Vault-Manifest.md')
# Top-level Tasks/ holds vault-tasks' Obsidian Tasks-plugin dashboard views (Active/Backlog/
# Blocked.md per area) - skill-owned query files, not authored documents, same reasoning as
# the Tasks.md exclusion above but expressed as a folder since the filenames differ per status.
# The hidden-folder scan (below) exists to cover the backend guides tier (.claude\guides);
# other hidden content is not authored vault documents: skill docs are harness contract,
# .myai is external tooling, .vault holds skill output data (e.g. rendered transcripts).
$provenanceExcludePaths = @('Tasks', '.claude\skills', '.myai', '.vault', '.pytest_cache')

$repaired       = @()  # Check 1: created/archived recovered - written if -Update, previewed otherwise
$manual         = @()  # Check 1: recovery chain exhausted, needs a human
$missingCreated = @()  # Check 2: vault-wide, report-only
$missingType    = @()  # Check 3: vault-wide, report-only
$staleUseSkill  = @()  # Check 4: archived file still carries a use_skill: entry - written if -Update, previewed otherwise

Get-VaultMarkdownFiles -VaultRoot $vaultRoot -PathOverride $PathOverride `
    -ExcludeFiles $provenanceExcludeFiles -ExcludePaths $provenanceExcludePaths -IncludeHiddenFolders |
    Where-Object { -not (Test-IsFolderNote $_) } |
    ForEach-Object {
        $rel     = $_.FullName.Substring($vaultRoot.Length)
        $relFwd  = $rel -replace '\\', '/'
        $content = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)

        # A pure Templater script (no markdown body at all) isn't an authored document - skip
        # it from all three checks, same as a folder note or Tasks.md.
        if (Test-IsTemplaterScript -Content $content) { return }

        $isArchive        = $relFwd -match '(^|/)Archive(/|$)'
        $created          = Get-FrontmatterField -Content $content -Field 'doc.created'
        # Tracks whether 'doc.created' will be present after this run - starts as the existing
        # value, updated below if Check 1 recovers it (whether or not -Update actually writes),
        # so Check 2 does not re-report a file Check 1 already resolves.
        $createdEffective = $created

        if ($isArchive) {
            # Single running buffer across Check 1 and Check 4, both of which may mutate this
            # file - one write at the end, not one per check, so a second check's write can't
            # clobber the first's.
            $newContent = $content
            $missing    = @()
            $writes     = @()

            $archived = Get-FrontmatterField -Content $content -Field 'doc.archived'
            if (-not $created) {
                $recovered = Get-CreatedDate -VaultRoot $vaultRoot -RelPath $rel -Content $content
                if ($recovered) {
                    $newContent = Set-FrontmatterField -Content $newContent -Field 'doc.created' -Value $recovered
                    $writes += "doc.created: $recovered"
                    $createdEffective = $recovered
                } else {
                    $missing += 'doc.created'
                }
            }
            if (-not $archived) {
                $recovered = Get-ArchivedDate -VaultRoot $vaultRoot -RelPath $rel -Content $content
                if ($recovered) {
                    $newContent = Set-FrontmatterField -Content $newContent -Field 'doc.archived' -Value $recovered
                    $writes += "doc.archived: $recovered"
                } else {
                    $missing += 'doc.archived'
                }
            }

            # Check 4: independent of the created/archived repair above - a file can be fully
            # provenance-complete and still carry a stale use_skill: entry, or vice versa.
            $skillStripped = Remove-UseSkillAgentInstructions -Content $newContent
            if ($skillStripped -ne $newContent) {
                $newContent = $skillStripped
                $staleUseSkill += $rel
            }

            if ($newContent -ne $content -and $Update) {
                [System.IO.File]::WriteAllText($_.FullName, $newContent, $Utf8NoBom)
            }
            if ($writes.Count -gt 0) {
                $repaired += [PSCustomObject]@{ File = $rel; Fields = ($writes -join ', ') }
            }
            if ($missing.Count -gt 0) {
                $manual += [PSCustomObject]@{ File = $rel; Missing = ($missing -join ', ') }
            }
        }

        if (-not $createdEffective -and -not (Test-IsTemplateDoc -RelPath $rel)) {
            $missingCreated += $rel
        }

        # Check 3: Guide docs are excluded (same reasoning as folder notes - structural, not
        # part of the doc.* schema; see Document-Conventions.md's Provenance Frontmatter
        # section). Everything else, including files with a filename date, is in scope.
        if (-not (Test-IsGuideDoc -RelPath $rel) -and -not (Test-IsTemplateDoc -RelPath $rel)) {
            $type = Get-FrontmatterField -Content $content -Field 'doc.type'
            if (-not $type) {
                $missingType += $rel
            }
        }
    }

Write-Host "== Check 1: Archive Provenance =="
if ($repaired.Count -eq 0 -and $manual.Count -eq 0) {
    Write-Host "No archive provenance violations found."
} else {
    $verb = if ($Update) { 'Repaired' } else { 'Would repair' }
    foreach ($r in $repaired) { Write-Host "${verb}: $($r.File) ($($r.Fields))" }
    foreach ($m in $manual)   { Write-Host "Manual resolution needed: $($m.File) (missing: $($m.Missing))" }
    Write-Host ""
    Write-Host "$($repaired.Count) repaired, $($manual.Count) needing manual resolution."
}

Write-Host ""
Write-Host "== Check 2: Vault-Wide Created (report-only) =="
if ($missingCreated.Count -eq 0) {
    Write-Host "No files missing 'doc.created:' found."
} else {
    foreach ($f in $missingCreated) { Write-Host "Missing 'doc.created:': $f" }
    Write-Host ""
    Write-Host "$($missingCreated.Count) file(s) missing 'doc.created:'."
}

Write-Host ""
Write-Host "== Check 3: Vault-Wide Type (report-only) =="
if ($missingType.Count -eq 0) {
    Write-Host "No files missing 'doc.type:' found."
} else {
    foreach ($f in $missingType) { Write-Host "Missing 'doc.type:': $f" }
    Write-Host ""
    Write-Host "$($missingType.Count) file(s) missing 'doc.type:'."
}

Write-Host ""
Write-Host "== Check 4: Stale Archived use_skill: Entries =="
if ($staleUseSkill.Count -eq 0) {
    Write-Host "No archived files with a stale 'use_skill:' entry found."
} else {
    $verb = if ($Update) { 'Stripped' } else { 'Would strip' }
    foreach ($f in $staleUseSkill) { Write-Host "${verb}: $f" }
    Write-Host ""
    Write-Host "$($staleUseSkill.Count) file(s) with a stale 'use_skill:' entry."
}
