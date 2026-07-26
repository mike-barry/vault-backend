# Programmatic schema-conformance check for the agent.* / nav.* frontmatter layer.
# Owned by the vault-agent-frontmatter skill (the schema lives here); invoked by vault-lint as
# its frontmatter section. Report-only - prints violations, never edits files.
#
# Scope: deterministic checks only. Subjective detection (e.g. agent instructions embedded
# in a note body) is deliberately out of scope - that stays an authoring rule. Frontmatter
# wikilink resolution is handled by vault-lint's check-broken-wikilinks.ps1, which already
# scans whole-file content including quoted, path-qualified [[...]] links.
#
# Two directions of folder-note completeness are checked: a declared `folder:` path that no
# longer resolves (per-entry), and a standard subfolder that physically exists but has no
# entry (folder-note completeness, below) - ephemeral folders are emitted with a ready-to-add
# boilerplate block, Ref members and non-standard folders are surfaced for the user to resolve.
# Corpus membership resolves transitively through intermediate folder notes (Expand-CorpusLinkReach).
# Reporting stays report-only; the auto-add edit itself is applied by vault-lint via the agent.
param(
    # Vault-relative folder to scope the scan (e.g. 'Areas/Personal'). When omitted, the
    # configured include folders are scanned. Used by tests and ad-hoc runs.
    [string]$PathOverride,
    # Vault root directory. Auto-resolved from the script location when not specified; pass
    # explicitly for non-default locations such as a test worktree.
    [string]$VaultRootOverride
)

$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-common.ps1')
. (Join-Path $_skillDir '..' '_shared' 'vault-frontmatter.ps1')

$vaultRoot = if ($VaultRootOverride) { $VaultRootOverride } else { Get-VaultRoot $PSScriptRoot }
# Guarantee a trailing separator so Substring($vaultRoot.Length) yields a clean relative path.
# Get-VaultRoot already does this; an explicit override may not, which would leave a leading
# separator that breaks path comparisons in the folder-note completeness scan.
$vaultRoot = $vaultRoot.TrimEnd('\', '/') + '\'

# File enumeration config - mirrors vault-lint's (lint-common.ps1). Templates carry literal
# placeholder frontmatter; Document-Conventions points at the schema rather than encoding it.
$includeFolders = @('Archive', 'Areas', 'Projects', 'Resources', '.claude\guides')
$excludeFiles   = @('Document-Conventions.md')
$excludePaths   = @('Resources\Vault\Templates')

# The complete agent.* / nav.* schema, encoded once here (the source of truth is
# Frontmatter-Schema.md, which this list conforms to).
$knownKeys      = @('agent.instructions', 'nav.contents', 'nav.see_also')
$navKeys        = @('nav.contents', 'nav.see_also')
$entryFields    = @('link', 'folder', 'description', 'load_when')
$pinnedFields   = @('pinned')
$skillFields    = @('use_skill', 'when', 'note')

# Standard subfolders a folder note is expected to account for, and the completeness rule
# for each. The ephemeral folders below route via a single `folder:` entry, so a missing one
# is auto-addable with the boilerplate `description` / `load_when` recorded here. 'Corpus' is
# the contrast: a durable corpus whose members each get their own `link`, so it is checked
# per-member (see $corpusFolderName), never as a single folder entry. Any other (non-standard)
# subfolder is surfaced for interactive resolution rather than auto-added.
$ephemeralBoilerplate = [ordered]@{
    Inbox   = @{ description = 'Active working docs and in-flight content';       load_when = 'working on in-progress tasks or finding a specific artifact' }
    Archive = @{ description = 'Completed and inactive artifacts, date-prefixed'; load_when = 'researching prior artifacts or project history' }
}
$corpusFolderName = 'Corpus'

# ---------------------------------------------------------------------------
# Minimal frontmatter parser
#
# PowerShell has no built-in YAML and the vault avoids external module deps, so this parses
# the constrained shape the schema actually uses: dot-namespaced top-level keys whose values
# are block sequences of either bare strings (agent.*) or nested objects (nav entries).
#
# Get-FrontmatterLines, Remove-Quotes, Get-FrontmatterBlocks, and Get-FrontmatterListItems
# (fence-block extraction, scalar unquoting, and the block/list-item parsers) live in
# _shared/vault-frontmatter.ps1 - shared with Add-AgentInstructionEntry, which writes the
# same shape this script validates.
# ---------------------------------------------------------------------------

# Last path segment of a wikilink target, alias/anchor stripped:
# '[[Corpus/Task-System|x]]' -> 'Task-System', '[[Vision]]' -> 'Vision'. $null when not a link.
# Reducing to the basename is how the vault itself resolves a link (glob '**/Name.md'), so the
# bare and path-qualified forms of the same target - '[[Tools]]' and
# '[[Vault-MCP-Server/Corpus/Tools]]' - collapse to one comparable key.
function Get-LinkBasename {
    param([string]$Link)
    if ($Link -match '\[\[([^\]]+)\]\]') {
        $inner = (($Matches[1] -split '\|')[0] -split '#')[0].Trim()
        if ($inner) { return (Split-Path $inner -Leaf) }
    }
    return $null
}

# Lowercased link basenames a note declares across its nav.* blocks. A `folder:` entry is not a
# link, so it is skipped here (the folder-note completeness scan tracks those separately).
function Get-NavLinkBasenames {
    param($Blocks)
    $set = New-Object System.Collections.Generic.HashSet[string]
    $map = @{}
    foreach ($b in $Blocks) { $map[$b.Key] = $b }
    foreach ($nk in $navKeys) {
        if (-not $map.ContainsKey($nk)) { continue }
        foreach ($it in (Get-FrontmatterListItems $map[$nk].Children)) {
            if (-not $it.IsMap) { continue }
            if ($it.Fields.Contains('folder') -and $it.Fields['folder']) { continue }
            if ($it.Fields.Contains('link')) {
                $lb = Get-LinkBasename $it.Fields['link']
                if ($lb) { [void]$set.Add($lb.ToLowerInvariant()) }
            }
        }
    }
    return $set
}

# Corpus routing may go one or more hops through an intermediate folder note: the note under
# scan links a Corpus subfolder's folder note, and that note's own nav.contents routes on to the
# members inside it. Expand $Declared into every link basename reachable that way.
#
# Only a *folder note* (basename == its parent folder's name) is stepped through. Routing is a
# folder note's job; an ordinary Corpus doc that name-drops a sibling in its nav.see_also is a
# prose cross-reference, and traversing those would let any member silently satisfy the check
# for any other. Intermediates are looked up among $Members - the Corpus subtree already being
# enumerated - which both matches basename resolution and keeps the lookup free of vault-wide
# basename ambiguity. $visited terminates a cycle between two folder notes that link each other.
function Expand-CorpusLinkReach {
    param($Declared, $Members)
    $folderNotes = @{}
    foreach ($m in $Members) {
        if (Test-IsFolderNote $m) { $folderNotes[$m.BaseName.ToLowerInvariant()] = $m }
    }
    $reach   = New-Object System.Collections.Generic.HashSet[string]
    $visited = New-Object System.Collections.Generic.HashSet[string]
    $queue   = New-Object System.Collections.Generic.Queue[string]
    foreach ($n in @($Declared)) { if ($reach.Add($n)) { $queue.Enqueue($n) } }
    while ($queue.Count -gt 0) {
        $n = $queue.Dequeue()
        if (-not $folderNotes.ContainsKey($n)) { continue }
        if (-not $visited.Add($n)) { continue }
        $hop = $folderNotes[$n]
        $hopFm = Get-FrontmatterLines ([System.IO.File]::ReadAllText($hop.FullName, [System.Text.Encoding]::UTF8))
        if ($null -eq $hopFm) { continue }
        foreach ($lb in (Get-NavLinkBasenames (Get-FrontmatterBlocks $hopFm))) {
            if ($reach.Add($lb)) { $queue.Enqueue($lb) }
        }
    }
    return $reach
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

$violations = @()
function Add-Violation { param([string]$File, [string]$Message) $script:violations += [PSCustomObject]@{ File = $File; Message = $Message } }

# Deliberately-excluded paths, normalized for the folder-note completeness scan so it does not
# flag a special folder (e.g. Templates) that is intentionally outside the lint scope.
$excludedCmp = @($excludePaths | ForEach-Object { ConvertTo-ComparablePath $_ })

# Vault-relative subfolder paths that are intentionally unreferenced in their parent folder
# note. One path per line; '#' starts a comment. Add here to suppress a known-intentional
# 'Unreferenced non-standard subfolder' finding without adding a nav entry for it.
$ignoredSubfoldersFile = Join-Path $vaultRoot '.vault\state\vault-lint\known-ignored-subfolders.txt'
$ignoredSubfoldersCmp  = if (Test-Path $ignoredSubfoldersFile) {
    @((Get-Content $ignoredSubfoldersFile) |
        Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } |
        ForEach-Object { ConvertTo-ComparablePath $_.Trim() })
} else { @() }

Get-VaultMarkdownFiles -VaultRoot $vaultRoot -PathOverride $PathOverride `
    -IncludeFolders $includeFolders -ExcludeFiles $excludeFiles -ExcludePaths $excludePaths | ForEach-Object {

    $rel = $_.FullName.Substring($vaultRoot.Length)
    $content = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    $fmLines = Get-FrontmatterLines $content
    $blocks  = if ($null -ne $fmLines) { Get-FrontmatterBlocks $fmLines } else { @() }

    $byKey = @{}
    foreach ($b in $blocks) { $byKey[$b.Key] = $b }

    # Skill-owned Tasks.md must carry its vault-tasks use_skill: directive (keyed off the
    # literal filename). Absence is a violation here - unlike other fields, where absence is
    # valid. Archived Tasks.md is excluded: vault-doc-archive strips use_skill: entries at
    # archive time (vault-lint step 7 Check 4 catches drift), so a stripped directive there is
    # correct, not a violation - same '(^|/)Archive(/|$)' path match check-provenance.ps1 uses
    # to scope its own Archive-only checks.
    $relFwd = $rel -replace '\\', '/'
    if ($_.Name -eq 'Tasks.md' -and $relFwd -notmatch '(^|/)Archive(/|$)') {
        $ok = $false
        if ($byKey.ContainsKey('agent.instructions')) {
            $items = Get-FrontmatterListItems $byKey['agent.instructions'].Children
            $ok = [bool]($items | Where-Object { $_.IsMap -and $_.Fields.Contains('use_skill') -and $_.Fields['use_skill'] -match 'vault-tasks' })
        }
        if (-not $ok) {
            Add-Violation $rel "Tasks.md missing its agent.instructions 'use_skill: vault-tasks' directive"
        }
    }

    foreach ($b in $blocks) {
        $key = $b.Key
        # Only the agent.*/nav.* namespace is in scope; lifecycle/top-level fields are ignored.
        if ($key -notmatch '^(agent|nav)\.') { continue }
        if ($knownKeys -notcontains $key) {
            Add-Violation $rel "Unknown frontmatter key '$key' (not in the agent.*/nav.* schema)"
            continue
        }

        # Presence means content: every known key is a non-empty block list. An empty list,
        # an empty-marker inline (`[]`), or a stray inline scalar are all malformed.
        $items = @()
        if ($b.Inline -eq '') {
            $items = Get-FrontmatterListItems $b.Children
            if ($items.Count -eq 0) {
                Add-Violation $rel "Empty '$key' - omit the field instead (presence means content)"
                continue
            }
        } elseif ($b.Inline -in @('[]', "''", '""')) {
            Add-Violation $rel "Empty placeholder '$($key): $($b.Inline)' - omit the field instead (presence means content)"
            continue
        } else {
            Add-Violation $rel "'$key' should be a block list, found inline value '$($b.Inline)'"
            continue
        }

        if ($navKeys -contains $key) {
            $idx = 0
            foreach ($it in $items) {
                $idx++
                if (-not $it.IsMap) {
                    Add-Violation $rel "$key entry #$idx is a bare string, expected a link/folder object"
                    continue
                }
                $hasLink   = $it.Fields.Contains('link')
                $hasFolder = $it.Fields.Contains('folder')
                if ($hasLink -and $hasFolder) {
                    Add-Violation $rel "$key entry #$idx has both 'link' and 'folder' (exactly one required)"
                } elseif (-not $hasLink -and -not $hasFolder) {
                    Add-Violation $rel "$key entry #$idx has neither 'link' nor 'folder'"
                }
                if (-not $it.Fields.Contains('description') -or [string]::IsNullOrWhiteSpace($it.Fields['description'])) {
                    Add-Violation $rel "$key entry #$idx is missing 'description'"
                }
                foreach ($f in @($it.Fields.Keys)) {
                    if ($entryFields -notcontains $f) {
                        Add-Violation $rel "$key entry #$idx has unknown field '$f'"
                    }
                }
                # A folder entry's repo-relative path must point at a real directory.
                if ($hasFolder) {
                    $fp  = $it.Fields['folder']
                    $abs = Join-Path $vaultRoot $fp
                    if (-not (Test-Path -LiteralPath $abs -PathType Container)) {
                        Add-Violation $rel "$key entry #$idx folder path does not resolve: '$fp'"
                    }
                }
            }
        } elseif ($key -eq 'agent.instructions') {
            # Each entry is a bare string (revisable hint) or a discriminated object:
            # pinned: (human, frozen) or use_skill:/when:/note: (skill-authored, frozen).
            $idx = 0
            foreach ($it in $items) {
                $idx++
                if (-not $it.IsMap) { continue }
                $hasPinned = $it.Fields.Contains('pinned')
                $hasSkill  = $it.Fields.Contains('use_skill')
                if ($hasPinned -and $hasSkill) {
                    Add-Violation $rel "agent.instructions entry #$idx has both 'pinned' and 'use_skill' (exactly one discriminator allowed)"
                } elseif ($hasPinned) {
                    foreach ($f in @($it.Fields.Keys)) {
                        if ($pinnedFields -notcontains $f) {
                            Add-Violation $rel "agent.instructions entry #$idx (pinned) has unexpected field '$f'"
                        }
                    }
                } elseif ($hasSkill) {
                    if (-not $it.Fields.Contains('when') -or [string]::IsNullOrWhiteSpace($it.Fields['when'])) {
                        Add-Violation $rel "agent.instructions entry #$idx (use_skill) is missing 'when'"
                    }
                    foreach ($f in @($it.Fields.Keys)) {
                        if ($skillFields -notcontains $f) {
                            Add-Violation $rel "agent.instructions entry #$idx (use_skill) has unexpected field '$f'"
                        }
                    }
                } else {
                    Add-Violation $rel "agent.instructions entry #$idx is an object but has neither 'pinned' nor 'use_skill'"
                }
            }
        }
    }

    # -----------------------------------------------------------------------
    # Standard-folder completeness (folder notes only)
    #
    # A folder note lives at <Dir>/<Dir>.md and its job is to route to its children. Compare
    # the subfolders that physically exist under <Dir> against the entries the note declares:
    #   - a standard ephemeral folder (Inbox/Archive) with no `folder:` entry is
    #     auto-addable - emit the ready-to-insert block with house-style boilerplate;
    #   - a 'Corpus' member the note does not reach by link is surfaced for interactive
    #     resolution (Corpus is per-member links, never a single folder entry); reach is
    #     transitive through an intermediate folder note - see Expand-CorpusLinkReach;
    #   - any other unreferenced subfolder is surfaced for interactive resolution.
    # The reverse direction (a declared `folder:` path that no longer resolves) is handled by
    # the per-entry check above.
    # -----------------------------------------------------------------------
    $parentDir = Split-Path $_.FullName -Parent
    if (Test-IsFolderNote $_) {
        # The folder paths and link basenames this note already declares.
        $declaredFolders = New-Object System.Collections.Generic.HashSet[string]
        foreach ($nk in $navKeys) {
            if (-not $byKey.ContainsKey($nk)) { continue }
            foreach ($it in (Get-FrontmatterListItems $byKey[$nk].Children)) {
                if (-not $it.IsMap) { continue }
                if ($it.Fields.Contains('folder') -and $it.Fields['folder']) {
                    [void]$declaredFolders.Add((ConvertTo-ComparablePath $it.Fields['folder']))
                }
            }
        }
        $declaredLinks = Get-NavLinkBasenames $blocks

        Get-ChildItem -LiteralPath $parentDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Name.StartsWith('.') } | ForEach-Object {
            $childDir = $_
            $childRel = ($childDir.FullName.Substring($vaultRoot.Length)) -replace '\\', '/'
            $childCmp = ConvertTo-ComparablePath $childRel
            $name     = $childDir.Name
            if ($excludedCmp -contains $childCmp) { return }

            if ($ephemeralBoilerplate.Contains($name)) {
                if (-not $declaredFolders.Contains($childCmp)) {
                    $bp = $ephemeralBoilerplate[$name]
                    Add-Violation $rel ("Missing folder entry (auto-add) for standard folder '$name'. Add to nav.contents:`n" +
                        "         - folder: `"$childRel`"`n" +
                        "           description: `"$($bp.description)`"`n" +
                        "           load_when: `"$($bp.load_when)`"")
                }
            } elseif ($name -eq $corpusFolderName) {
                $members = @(Get-ChildItem -LiteralPath $childDir.FullName -Recurse -Filter '*.md' -ErrorAction SilentlyContinue)
                # Membership resolves transitively: directly linked, or linked by a folder note
                # this note (directly or transitively) links. See Expand-CorpusLinkReach.
                $reachable = Expand-CorpusLinkReach $declaredLinks $members
                foreach ($m in $members) {
                    if (-not $reachable.Contains($m.BaseName.ToLowerInvariant())) {
                        $mrel = ($m.FullName.Substring($vaultRoot.Length)) -replace '\\', '/'
                        Add-Violation $rel "Corpus member without a link entry (resolve interactively): '$mrel' - add a 'link' entry for it or confirm it should stay unlinked"
                    }
                }
            } else {
                $referenced = $declaredFolders.Contains($childCmp) -or $declaredLinks.Contains($name.ToLowerInvariant())
                if (-not $referenced -and ($ignoredSubfoldersCmp -notcontains $childCmp)) {
                    Add-Violation $rel "Unreferenced non-standard subfolder (resolve interactively): '$childRel' - add a link/folder entry or confirm it is intentionally omitted"
                }
            }
        }
    }
}

if ($violations.Count -eq 0) {
    Write-Host "No frontmatter schema violations found."
} else {
    foreach ($v in $violations) {
        Write-Host "Violation: $($v.File)"
        Write-Host "  -> $($v.Message)"
    }
    Write-Host ""
    Write-Host "$($violations.Count) frontmatter violation(s) found."
}
