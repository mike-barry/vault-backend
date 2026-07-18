# vault-frontmatter.ps1
# Shared helpers for reading and writing vault frontmatter content: fence-block extraction,
# flat scalar field get/set/remove, and the doc.created/doc.archived date-recovery chains.
# Dot-source this file from any skill script that needs it (it is not pulled in by
# lint-common.ps1's default chain):
#   $_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
#   . (Join-Path $_skillDir '..' '_shared' 'vault-frontmatter.ps1')
#
# Dot-sources vault-common.ps1 itself (Get-CreatedDate needs Get-FilenameDate from there) -
# callers do not need to dot-source vault-common.ps1 separately.

. (Join-Path $PSScriptRoot 'vault-common.ps1')

# Return the lines between the opening '---' fence and the next '---', or $null when the
# content has no (closed) frontmatter block.
function Get-FrontmatterLines {
    param([string]$Content)
    $lines = $Content -split "`r?`n"
    if ($lines.Count -lt 1 -or $lines[0].Trim() -ne '---') { return $null }
    $fm = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { return , $fm.ToArray() }
        $fm.Add($lines[$i])
    }
    return $null
}

# Strip a single layer of matching surrounding quotes from a scalar value.
function Remove-Quotes {
    param([string]$Value)
    $v = $Value.Trim()
    if ($v.Length -ge 2 -and
        (($v[0] -eq '"' -and $v[$v.Length - 1] -eq '"') -or
         ($v[0] -eq "'" -and $v[$v.Length - 1] -eq "'"))) {
        return $v.Substring(1, $v.Length - 2)
    }
    return $v
}

# Read a flat top-level scalar field (e.g. 'doc.created', 'doc.archived') from frontmatter content.
# Returns $null when the field, or the frontmatter block itself, is absent or empty.
function Get-FrontmatterField {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Field
    )
    $fmLines = Get-FrontmatterLines $Content
    if ($null -eq $fmLines) { return $null }
    foreach ($line in $fmLines) {
        if ($line -match "^$([regex]::Escape($Field)):\s*(.*)$") {
            $v = Remove-Quotes $Matches[1]
            if ($v -eq '') { return $null }
            return $v
        }
    }
    return $null
}

# Write a flat top-level scalar field into frontmatter content: updates the field in place if
# present, appends it just before the closing fence if the block exists but the field does
# not, or creates a new frontmatter block at the top of the file if none exists. Returns the
# updated content - does not write to disk. Existing fields and their order are preserved.
function Set-FrontmatterField {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Field,
        [Parameter(Mandatory)][string]$Value
    )
    $lines = $Content -split "`r?`n"
    if ($lines.Count -ge 1 -and $lines[0].Trim() -eq '---') {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^$([regex]::Escape($Field)):\s*(.*)$") {
                $lines[$i] = "$($Field): $Value"
                return ($lines -join "`n")
            }
            if ($lines[$i].Trim() -eq '---') {
                $before = if ($i -gt 0) { $lines[0..($i - 1)] } else { @() }
                $after  = $lines[$i..($lines.Count - 1)]
                return (($before + "$($Field): $Value" + $after) -join "`n")
            }
        }
        # Fence never closed - fall through and treat as no frontmatter block.
    }
    return ((@('---', "$($Field): $Value", '---') + $lines) -join "`n")
}

# Remove a flat top-level scalar field from frontmatter content, if present. Returns the
# updated content unchanged when the field or the frontmatter block itself is absent.
function Remove-FrontmatterField {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Field
    )
    $lines = $Content -split "`r?`n"
    if ($lines.Count -lt 1 -or $lines[0].Trim() -ne '---') { return $Content }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { return $Content }
        if ($lines[$i] -match "^$([regex]::Escape($Field)):\s*(.*)$") {
            $kept = $lines[0..($i - 1)] + $lines[($i + 1)..($lines.Count - 1)]
            return ($kept -join "`n")
        }
    }
    return $Content
}

# Remove an entire block-list field (its key line plus all indented children), if present -
# the block-aware counterpart to Remove-FrontmatterField, which only handles single-line flat
# scalars and would corrupt a block field (e.g. 'agent.pinned_instructions:') by deleting the
# key line and leaving its now-unkeyed indented children behind. Returns the updated content
# unchanged when the field or the frontmatter block itself is absent.
function Remove-FrontmatterBlock {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Field
    )
    $lines = $Content -split "`r?`n"
    if ($lines.Count -lt 1 -or $lines[0].Trim() -ne '---') { return $Content }
    $fenceEnd = $null
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $fenceEnd = $i; break }
    }
    if ($null -eq $fenceEnd) { return $Content }

    $keyLine = $null
    for ($i = 1; $i -lt $fenceEnd; $i++) {
        if ($lines[$i] -match "^$([regex]::Escape($Field)):") { $keyLine = $i; break }
    }
    if ($null -eq $keyLine) { return $Content }

    $blockEnd = $keyLine
    for ($i = $keyLine + 1; $i -lt $fenceEnd; $i++) {
        if ($lines[$i] -match '^[A-Za-z0-9_.]+:') { break }
        $blockEnd = $i
    }

    $kept = @()
    if ($keyLine -gt 0) { $kept += $lines[0..($keyLine - 1)] }
    if ($blockEnd + 1 -le $lines.Count - 1) { $kept += $lines[($blockEnd + 1)..($lines.Count - 1)] }
    return ($kept -join "`n")
}

# Split frontmatter lines into top-level blocks: @{ Key; Inline; Children=@(raw indented
# lines) }. Generalized top-level dot-namespaced key/block splitter for the constrained
# frontmatter shape the schema uses (dot-namespaced top-level keys whose values are block
# sequences of bare strings or nested objects). Shared by validate-frontmatter.ps1 (read) and
# Add-AgentInstructionEntry below (write) so both consume the same parse.
function Get-FrontmatterBlocks {
    param([string[]]$FmLines)
    $blocks = @()
    $cur = $null
    foreach ($line in $FmLines) {
        if ($line -match '^[A-Za-z0-9_.]' -and $line -match '^([A-Za-z0-9_.]+):(.*)$') {
            if ($cur) { $blocks += $cur }
            $cur = @{ Key = $Matches[1]; Inline = $Matches[2].Trim(); Children = @() }
        } elseif ($null -ne $cur -and $line.Trim() -ne '') {
            $cur.Children += $line
        }
    }
    if ($cur) { $blocks += $cur }
    return $blocks
}

# Parse a block's child lines into list items. Each item is either a bare scalar
# (@{ IsMap=$false; Scalar }) or a nested object (@{ IsMap=$true; Fields=[ordered] }).
function Get-FrontmatterListItems {
    param([string[]]$Children)
    $items = @()
    $cur = $null
    foreach ($line in $Children) {
        if ($line -match '^\s*-\s*(.*)$') {
            if ($cur) { $items += $cur }
            $rest = $Matches[1]
            if ($rest -match '^([A-Za-z0-9_]+):\s*(.*)$') {
                $cur = @{ IsMap = $true; Fields = [ordered]@{} }
                $cur.Fields[$Matches[1]] = (Remove-Quotes $Matches[2])
            } else {
                $cur = @{ IsMap = $false; Scalar = (Remove-Quotes $rest) }
            }
        } elseif ($null -ne $cur -and $cur.IsMap -and $line -match '^\s+([A-Za-z0-9_]+):\s*(.*)$') {
            $cur.Fields[$Matches[1]] = (Remove-Quotes $Matches[2])
        }
    }
    if ($cur) { $items += $cur }
    return , $items
}

# Insert one discriminated entry into a file's agent.instructions block, creating the block
# if absent. Idempotent: an entry identical to one already present (same Bare/Pinned text, or
# same UseSkill+When for a UseSkill entry) is a no-op, so callers can invoke this
# unconditionally during backfill without checking first. Returns updated content - does not
# write to disk, same convention as Set-FrontmatterField.
function Add-AgentInstructionEntry {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][ValidateSet('Bare', 'Pinned', 'UseSkill')][string]$Type,
        # Bare or Pinned - the entry's text.
        [string]$Instruction,
        # UseSkill.
        [string]$UseSkill,
        # UseSkill, required.
        [string]$When,
        # UseSkill, optional.
        [string]$Note
    )
    if ($Type -in @('Bare', 'Pinned') -and [string]::IsNullOrWhiteSpace($Instruction)) {
        throw "Add-AgentInstructionEntry: -Instruction is required for -Type $Type"
    }
    if ($Type -eq 'UseSkill' -and ([string]::IsNullOrWhiteSpace($UseSkill) -or [string]::IsNullOrWhiteSpace($When))) {
        throw 'Add-AgentInstructionEntry: -UseSkill and -When are required for -Type UseSkill'
    }

    $newLines = switch ($Type) {
        'Bare'   { , "  - `"$Instruction`"" }
        'Pinned' { , "  - pinned: `"$Instruction`"" }
        'UseSkill' {
            $l = @("  - use_skill: `"$UseSkill`"", "    when: `"$When`"")
            if (-not [string]::IsNullOrWhiteSpace($Note)) { $l += "    note: `"$Note`"" }
            , $l
        }
    }

    $lines = $Content -split "`r?`n"
    $hasFence = $lines.Count -ge 1 -and $lines[0].Trim() -eq '---'
    $fmLines = if ($hasFence) { Get-FrontmatterLines $Content } else { $null }

    if ($null -eq $fmLines) {
        # No frontmatter block at all - create one at the top of the file.
        return ((@('---', 'agent.instructions:') + $newLines + @('---') + $lines) -join "`n")
    }

    $blocks = Get-FrontmatterBlocks $fmLines
    $existing = $blocks | Where-Object { $_.Key -eq 'agent.instructions' } | Select-Object -First 1
    if ($existing) {
        $items = Get-FrontmatterListItems $existing.Children
        $dup = $items | Where-Object {
            if ($Type -eq 'Bare') {
                -not $_.IsMap -and $_.Scalar -eq $Instruction
            } elseif ($Type -eq 'Pinned') {
                $_.IsMap -and $_.Fields.Contains('pinned') -and $_.Fields['pinned'] -eq $Instruction
            } else {
                $_.IsMap -and $_.Fields.Contains('use_skill') -and $_.Fields['use_skill'] -eq $UseSkill `
                    -and $_.Fields.Contains('when') -and $_.Fields['when'] -eq $When
            }
        }
        if ($dup) { return $Content }
    }

    $fenceEnd = $null
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $fenceEnd = $i; break }
    }

    $keyLine = $null
    for ($i = 1; $i -lt $fenceEnd; $i++) {
        if ($lines[$i] -match '^agent\.instructions:') { $keyLine = $i; break }
    }

    if ($null -ne $keyLine) {
        $blockEnd = $keyLine
        for ($i = $keyLine + 1; $i -lt $fenceEnd; $i++) {
            if ($lines[$i] -match '^[A-Za-z0-9_.]+:') { break }
            $blockEnd = $i
        }
        $before = $lines[0..$blockEnd]
        $after  = $lines[($blockEnd + 1)..($lines.Count - 1)]
        return (($before + $newLines + $after) -join "`n")
    } else {
        $before = $lines[0..($fenceEnd - 1)]
        $after  = $lines[$fenceEnd..($lines.Count - 1)]
        return (($before + 'agent.instructions:' + $newLines + $after) -join "`n")
    }
}

# Remove every use_skill:-typed entry from a file's agent.instructions block, leaving bare
# and pinned: entries untouched. A use_skill: entry routes live edits through the owning
# skill; once a doc is archived it is frozen (never rewritten), so the routing directive is
# stale and would otherwise mislead an agent into thinking edits should still go through that
# skill. If removing all use_skill: entries empties the block, the whole agent.instructions
# key is dropped rather than left as an empty list. Line-range based (not a reserialize from
# parsed items) so any bare/pinned entries are preserved byte-for-byte. Returns updated
# content - does not write to disk, same convention as Set-FrontmatterField. A no-op when
# there is no agent.instructions block or it has no use_skill: entries.
function Remove-UseSkillAgentInstructions {
    param([Parameter(Mandatory)][string]$Content)

    $lines = $Content -split "`r?`n"
    if ($lines.Count -lt 1 -or $lines[0].Trim() -ne '---') { return $Content }
    $fenceEnd = $null
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $fenceEnd = $i; break }
    }
    if ($null -eq $fenceEnd) { return $Content }

    $keyLine = $null
    for ($i = 1; $i -lt $fenceEnd; $i++) {
        if ($lines[$i] -match '^agent\.instructions:') { $keyLine = $i; break }
    }
    if ($null -eq $keyLine) { return $Content }

    $blockEnd = $keyLine
    for ($i = $keyLine + 1; $i -lt $fenceEnd; $i++) {
        if ($lines[$i] -match '^[A-Za-z0-9_.]+:') { break }
        $blockEnd = $i
    }
    # @()-wrapped around the whole if/else: a single-index range (one-line block) returns a
    # bare scalar string from PowerShell's array slicing, not a one-element array, and
    # wrapping only the branch's own output isn't enough - assigning the if/else statement's
    # result to a variable re-flattens a one-element array back to a scalar. Wrapping the
    # entire expression is what actually sticks. Without this, the loop below would index
    # into the string's characters instead of iterating one line.
    $childLines = @(if ($blockEnd -ge $keyLine + 1) { $lines[($keyLine + 1)..$blockEnd] } else { @() })

    # Split children into per-item line ranges (a new item starts at each top-level '  - ' line).
    $itemRanges = @()
    $curStart = $null
    for ($i = 0; $i -lt $childLines.Count; $i++) {
        if ($childLines[$i] -match '^\s*-\s') {
            if ($null -ne $curStart) { $itemRanges += , @($curStart, ($i - 1)) }
            $curStart = $i
        }
    }
    if ($null -ne $curStart) { $itemRanges += , @($curStart, ($childLines.Count - 1)) }

    $keptChildLines = @()
    foreach ($r in $itemRanges) {
        # @()-wrapped for the same reason as $childLines above - a single-line item (the
        # common case for a bare/pinned entry) would otherwise slice into its characters.
        $itemLines = @($childLines[$r[0]..$r[1]])
        if ($itemLines[0] -match '^\s*-\s*use_skill:') { continue }
        $keptChildLines += $itemLines
    }

    if ($keptChildLines.Count -eq $childLines.Count) { return $Content }

    if ($keptChildLines.Count -eq 0) {
        $kept = @()
        if ($keyLine -gt 0) { $kept += $lines[0..($keyLine - 1)] }
        if ($blockEnd + 1 -le $lines.Count - 1) { $kept += $lines[($blockEnd + 1)..($lines.Count - 1)] }
        return ($kept -join "`n")
    }

    $before = $lines[0..$keyLine]
    $after  = if ($blockEnd + 1 -le $lines.Count - 1) { $lines[($blockEnd + 1)..($lines.Count - 1)] } else { @() }
    return (($before + $keptChildLines + $after) -join "`n")
}

# Recover the creation date for a vault file, in priority order:
#   1. Existing 'doc.created' frontmatter - used as-is, no change.
#   2. A leading (YYYY-MM-DD-Title) or trailing (Title-YYYY-MM-DD) filename date segment.
#   3. The git commit date that first added the file anywhere (`git log --follow
#      --diff-filter=A`, oldest match across the full rename chain).
# Returns $null when none of the above resolve - callers should flag for manual resolution
# rather than guessing.
function Get-CreatedDate {
    param(
        # Vault root with trailing backslash, as returned by Get-VaultRoot.
        [Parameter(Mandatory)][string]$VaultRoot,
        # Vault-relative path to the file (forward or back slashes both accepted).
        [Parameter(Mandatory)][string]$RelPath,
        # Current file content, used for the existing-frontmatter check.
        [Parameter(Mandatory)][string]$Content
    )
    $existing = Get-FrontmatterField -Content $Content -Field 'doc.created'
    if ($existing) { return $existing }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($RelPath)
    $fnDate = Get-FilenameDate -BaseName $baseName
    if ($fnDate) { return $fnDate }

    $relFwd = $RelPath -replace '\\', '/'
    # git log lists commits newest-first; the oldest match is the true first-add date.
    $dates = @(git -C $VaultRoot log --follow --diff-filter=A --format=%as -- $relFwd 2>$null)
    if ($dates.Count -gt 0) { return $dates[-1] }

    return $null
}

# Recover the archive date for a vault file already living under an Archive/ folder, in
# priority order:
#   1. Existing 'doc.archived' frontmatter - used as-is, no change.
#   2. The git commit date where the file's path first crosses from outside any Archive/
#      folder to inside one, walking the full `--follow --name-status` rename chain oldest
#      to newest. This is deliberately not "the earliest commit at the current path" - a
#      file later rolled up by compact-archive.ps1's month/year compaction changes path
#      again after the true archive date, and the earliest-commit-at-current-path approach
#      picks up that later compaction date instead (confirmed empirically - see the plan).
# Returns $null when no such crossing is found - callers should flag for manual resolution
# rather than guessing.
function Get-ArchivedDate {
    param(
        # Vault root with trailing backslash, as returned by Get-VaultRoot.
        [Parameter(Mandatory)][string]$VaultRoot,
        # Vault-relative path to the file (forward or back slashes both accepted).
        [Parameter(Mandatory)][string]$RelPath,
        # Current file content, used for the existing-frontmatter check.
        [Parameter(Mandatory)][string]$Content
    )
    $existing = Get-FrontmatterField -Content $Content -Field 'doc.archived'
    if ($existing) { return $existing }

    $relFwd = $RelPath -replace '\\', '/'
    $raw = @(git -C $VaultRoot log --follow --name-status --format=%as -- $relFwd 2>$null)
    if ($raw.Count -eq 0) { return $null }

    # Parse into per-commit change lists, in the newest-first order git log emits.
    $commits = @()
    $cur = $null
    foreach ($line in $raw) {
        if ($line -match '^\d{4}-\d{2}-\d{2}$') {
            if ($cur) { $commits += $cur }
            $cur = [PSCustomObject]@{ Date = $line; Changes = @() }
        } elseif ($line.Trim() -ne '' -and $cur) {
            if ($line -match '^R\d*\t(.+)\t(.+)$') {
                $cur.Changes += [PSCustomObject]@{ IsRename = $true; OldPath = $Matches[1]; NewPath = $Matches[2] }
            }
            # Non-rename statuses (M/A/D) carry a single path and cannot represent a
            # crossing on their own - not needed for this walk.
        }
    }
    if ($cur) { $commits += $cur }

    # Walk oldest -> newest looking for the first rename whose old path is outside Archive/
    # and new path is inside it.
    [array]::Reverse($commits)
    foreach ($c in $commits) {
        foreach ($ch in $c.Changes) {
            if (-not $ch.IsRename) { continue }
            $oldInArchive = $ch.OldPath -match '(^|/)Archive(/|$)'
            $newInArchive = $ch.NewPath -match '(^|/)Archive(/|$)'
            if (-not $oldInArchive -and $newInArchive) { return $c.Date }
        }
    }

    return $null
}
