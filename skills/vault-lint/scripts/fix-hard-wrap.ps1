# Detects and fixes hard-wrapped (fixed-width) prose and list-item lines. Frontmatter, fenced
# code, tables, blockquotes/callouts, and headings are left untouched. Developer context: the
# detection/safety rules this implements are documented in Lint-System.md, in the primary
# vault's Vault-Dev corpus.

param(
    # Apply auto-fixable joins to disk. Without this switch (and without -InspectFile) the
    # script reports per-file counts only.
    [switch]$Update,
    # Vault-relative (or absolute) path to a single file. Prints full block detail for that
    # file instead of running the vault-wide/PathOverride-scoped summary. Mutually exclusive
    # with -Update.
    [string]$InspectFile,
    # Vault-relative folder to scope the scan (e.g. 'Areas/Personal'). When omitted, all
    # configured include folders are scanned.
    [string]$PathOverride,
    # Vault root directory. Auto-resolved from the script location when not specified; pass
    # explicitly for non-default locations such as a test worktree.
    [string]$VaultRootOverride
)

. "$PSScriptRoot\lint-common.ps1"

if ($Update -and $InspectFile) {
    Write-Error '-Update and -InspectFile are mutually exclusive.'
    exit 1
}

$listPrefixRegex = '^(\s*(?:[-*+]|\d+[.)])(?:\s+\[[ xX]\])?\s+)'

# A genuinely hard-wrapped line lands close to the wrapping tool's column on every line
# except the last; an intentionally short line (mini-heading, definition-list label, etc.)
# does not. Chosen conservatively above observed intentional-short-line lengths (~66 chars)
# and below observed genuine mid-paragraph wrap lengths (~82+ chars) in this vault - biased
# toward NOT joining when in doubt, since a missed join is a safe no-op but a wrong join
# risks corrupting content. Tune here if real content shows this needs adjusting.
$MinFullLineLength = 70

function Test-IsFullWidthLine {
    param([string]$Line)
    return $Line.TrimEnd().Length -ge $MinFullLineLength
}

# A line matching this is a `**Label:** value` definition-list-style item. Such a line never
# folds into a preceding sub-block, regardless of length - two adjacent bold-label lines are
# independent record fields, not a wrapped pair. (A genuine hard-wrap's continuation line is
# always plain prose, never a new bold-label opener, so this rule can't suppress a real wrap.)
$boldLabelPrefixRegex = '^\s*\*\*[^*\n]+:\*\*'

function Test-IsBoldLabelLine {
    param([string]$Line)
    return $Line -match $boldLabelPrefixRegex
}

# A line matching this is, in its entirety, a standalone markdown image reference (e.g. a
# screenshot embed under a numbered list step). Such a line never folds into a preceding
# sub-block either, regardless of length or matching continuation indentation - it's an
# intentionally separate reference, not a wrap continuation. (A genuine hard-wrap's
# continuation line is never *only* an image reference, so this rule can't suppress a real
# wrap. Anchored to the whole line so an inline image mid-sentence is unaffected.)
$imageEmbedLineRegex = '^\s*!\[[^\]]*\]\([^)]*\)\s*$'

function Test-IsImageEmbedLine {
    param([string]$Line)
    return $Line -match $imageEmbedLineRegex
}

# Split a file's lines into blank-line-delimited chunks, excluding frontmatter and fenced code
# regions entirely (those lines never become part of any chunk).
function Get-EligibleChunks {
    param([string[]]$Lines)

    $chunks = @()
    $n = $Lines.Count
    $i = 0

    if ($n -gt 0 -and $Lines[0].Trim() -eq '---') {
        $i = 1
        while ($i -lt $n -and $Lines[$i].Trim() -ne '---') { $i++ }
        if ($i -lt $n) { $i++ }
    }

    $inFence    = $false
    $fenceChar  = $null
    $fenceLen   = 0
    $current      = New-Object System.Collections.Generic.List[string]
    $currentStart = -1

    for (; $i -lt $n; $i++) {
        $line = $Lines[$i]

        if (-not $inFence -and $line -match '^\s*(`{3,}|~{3,})') {
            if ($current.Count -gt 0) {
                $chunks += , [PSCustomObject]@{ StartLine = $currentStart; Lines = $current.ToArray() }
                $current = New-Object System.Collections.Generic.List[string]
            }
            $inFence   = $true
            $fenceChar = $Matches[1].Substring(0, 1)
            $fenceLen  = $Matches[1].Length
            continue
        }

        if ($inFence) {
            $closeRegex = '^\s*[{0}]{{{1},}}\s*$' -f [regex]::Escape($fenceChar), $fenceLen
            if ($line -match $closeRegex) { $inFence = $false }
            continue
        }

        if ($line.Trim() -eq '') {
            if ($current.Count -gt 0) {
                $chunks += , [PSCustomObject]@{ StartLine = $currentStart; Lines = $current.ToArray() }
                $current = New-Object System.Collections.Generic.List[string]
            }
            continue
        }

        if ($current.Count -eq 0) { $currentStart = $i + 1 }
        $current.Add($line)
    }

    if ($current.Count -gt 0) {
        $chunks += , [PSCustomObject]@{ StartLine = $currentStart; Lines = $current.ToArray() }
    }

    return $chunks
}

# A chunk containing a table row, blockquote/callout, heading, or thematic break is skipped
# entirely - fixed-width formatting there may be intentional, or fixing it risks corruption.
function Test-ChunkDisqualified {
    param([string[]]$Lines)
    foreach ($l in $Lines) {
        if ($l -match '^\s*\|') { return $true }
        if ($l -match '^\s*>') { return $true }
        if ($l -match '^\s*#{1,6}(\s|$)') { return $true }
        if ($l -match '^\s*(-{3,}|\*{3,}|_{3,})\s*$') { return $true }
    }
    return $false
}

# Split one blank-line-delimited chunk into join-candidate sub-blocks. A list-marker line
# always starts a new sub-block (even if its indentation matches the running continuation
# column - a nested item must never be folded into its parent). A non-marker line folds into
# the current list item only when its leading whitespace exactly matches that item's
# continuation column AND the line already accumulated is full-width (Test-IsFullWidthLine);
# otherwise it starts a new sub-block. Plain (non-list) text folds into the running sub-block
# under the same full-width gate, so an intentionally short line (a mini-heading, a
# definition-list label) never absorbs whatever follows it.
function Split-ChunkIntoSubBlocks {
    param([string[]]$Lines)

    $subBlocks = @()
    $current        = @()
    $currentIsList  = $false
    $currentContCol = -1
    $currentOffset  = 0

    for ($k = 0; $k -lt $Lines.Count; $k++) {
        $line = $Lines[$k]

        if ($line -match $listPrefixRegex) {
            if ($current.Count -gt 0) {
                $subBlocks += , [PSCustomObject]@{ Offset = $currentOffset; Lines = $current }
            }
            $current        = @($line)
            $currentOffset  = $k
            $currentIsList  = $true
            $currentContCol = $Matches[1].Length
            continue
        }

        if ($current.Count -eq 0) {
            $current       = @($line)
            $currentOffset = $k
            $currentIsList = $false
            continue
        }

        if ($currentIsList) {
            $line -match '^(\s*)' | Out-Null
            $leadingLen = $Matches[1].Length
            if ($leadingLen -eq $currentContCol -and (Test-IsFullWidthLine $current[$current.Count - 1]) -and -not (Test-IsImageEmbedLine $line)) {
                $current += $line
            } else {
                $subBlocks += , [PSCustomObject]@{ Offset = $currentOffset; Lines = $current }
                $current       = @($line)
                $currentOffset = $k
                $currentIsList = $false
            }
        } else {
            if ((Test-IsFullWidthLine $current[$current.Count - 1]) -and -not (Test-IsBoldLabelLine $line) -and -not (Test-IsImageEmbedLine $line)) {
                $current += $line
            } else {
                $subBlocks += , [PSCustomObject]@{ Offset = $currentOffset; Lines = $current }
                $current       = @($line)
                $currentOffset = $k
                $currentIsList = $false
            }
        }
    }

    if ($current.Count -gt 0) {
        $subBlocks += , [PSCustomObject]@{ Offset = $currentOffset; Lines = $current }
    }

    return $subBlocks
}

# Join a candidate block's lines into one line, tracking backtick and wikilink state across
# the break points. Returns Safe/Text/Reason. See Corruption Safety rules:
#   - Balanced backticks/wikilinks -> safe, single-space join throughout (like ordinary prose).
#   - A break inside an unclosed note-link target -> no-space join (vault filenames have no
#     spaces, so the break inserted a gap rather than removing one).
#   - A break inside a note-link alias -> single-space join (behaves like ordinary prose).
#   - A break inside an embed (`![[...`) target -> always flag; attachment filenames can
#     contain spaces, so the safe join can't be assumed.
#   - Unbalanced backticks or a wikilink never closed within the block -> flag.
function Get-JoinedBlockResult {
    param([string[]]$Lines)

    $prepped = @($Lines[0])
    for ($k = 1; $k -lt $Lines.Count; $k++) {
        $prepped += ($Lines[$k] -replace '^\s+', '')
    }

    $backtickOpen = $false
    $linkState    = 'None'   # None | Target | Alias
    $isEmbed      = $false
    $unsafe       = $false
    $reason       = $null
    $sb           = New-Object System.Text.StringBuilder

    for ($li = 0; $li -lt $prepped.Count; $li++) {
        $line = $prepped[$li]
        $ci = 0
        while ($ci -lt $line.Length) {
            $c = $line[$ci]

            if ($c -eq '`') {
                $backtickOpen = -not $backtickOpen
                [void]$sb.Append($c)
                $ci++
                continue
            }

            if ($linkState -eq 'None' -and $c -eq '[' -and ($ci + 1) -lt $line.Length -and $line[$ci + 1] -eq '[') {
                $prevChar = if ($ci -gt 0) { $line[$ci - 1] } elseif ($sb.Length -gt 0) { $sb[$sb.Length - 1] } else { $null }
                $isEmbed   = ($prevChar -eq '!')
                $linkState = 'Target'
                [void]$sb.Append('[[')
                $ci += 2
                continue
            }

            if ($linkState -ne 'None' -and $c -eq ']' -and ($ci + 1) -lt $line.Length -and $line[$ci + 1] -eq ']') {
                [void]$sb.Append(']]')
                $linkState = 'None'
                $isEmbed   = $false
                $ci += 2
                continue
            }

            if ($linkState -eq 'Target' -and $c -eq '|') { $linkState = 'Alias' }

            [void]$sb.Append($c)
            $ci++
        }

        if ($li -lt ($prepped.Count - 1)) {
            if ($linkState -ne 'None' -and $isEmbed) {
                $unsafe = $true
                if (-not $reason) { $reason = 'break inside embed link' }
                [void]$sb.Append(' ')
            } elseif ($linkState -eq 'Target') {
                # no-space join: a vault note-link target never contains spaces.
            } else {
                [void]$sb.Append(' ')
            }
        }
    }

    if ($backtickOpen) {
        $unsafe = $true
        if (-not $reason) { $reason = 'unbalanced code span' }
    }
    if ($linkState -ne 'None') {
        $unsafe = $true
        $reason = if ($isEmbed) { 'unbalanced embed link' } else { 'unbalanced wikilink' }
    }

    return [PSCustomObject]@{ Safe = (-not $unsafe); Text = $sb.ToString(); Reason = $reason }
}

function Get-HardWrapFindings {
    param([string[]]$Lines)

    $findings = @()
    foreach ($chunk in (Get-EligibleChunks -Lines $Lines)) {
        if (Test-ChunkDisqualified -Lines $chunk.Lines) { continue }

        foreach ($sub in (Split-ChunkIntoSubBlocks -Lines $chunk.Lines)) {
            if ($sub.Lines.Count -lt 2) { continue }
            $result = Get-JoinedBlockResult -Lines $sub.Lines
            $findings += [PSCustomObject]@{
                StartLine = $chunk.StartLine + $sub.Offset
                LineCount = $sub.Lines.Count
                Safe      = $result.Safe
                Text      = $result.Text
                Reason    = $result.Reason
                Lines     = $sub.Lines
            }
        }
    }
    return $findings
}

function Read-FileLines {
    param([string]$Path)
    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $eol = if ($content -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $content -split "`r?`n"
    return [PSCustomObject]@{ Lines = $lines; Eol = $eol }
}

function Write-HardWrapFixes {
    param([string]$Path, [string[]]$Lines, [object[]]$Findings, [string]$Eol)

    $autoRecs = $Findings | Where-Object { $_.Safe } | Sort-Object StartLine
    $newLines = New-Object System.Collections.Generic.List[string]
    $idx = 0
    foreach ($rec in $autoRecs) {
        $startIdx0 = $rec.StartLine - 1
        while ($idx -lt $startIdx0) { $newLines.Add($Lines[$idx]); $idx++ }
        $newLines.Add($rec.Text)
        $idx += $rec.LineCount
    }
    while ($idx -lt $Lines.Count) { $newLines.Add($Lines[$idx]); $idx++ }

    $newContent = [string]::Join($Eol, $newLines)
    [System.IO.File]::WriteAllText($Path, $newContent, $Utf8NoBom)
}

if ($InspectFile) {
    $vaultRoot = if ($VaultRootOverride) { $VaultRootOverride } else { Get-VaultRoot $PSScriptRoot }
    $path = Resolve-VaultPath -VaultRoot $vaultRoot -Path $InspectFile
    if (-not (Test-Path $path)) {
        Write-Error "File not found: $InspectFile"
        exit 1
    }
    $f = Read-FileLines -Path $path
    $findings = Get-HardWrapFindings -Lines $f.Lines

    if ($findings.Count -eq 0) {
        Write-Host "No hard-wrapped blocks found in $InspectFile."
    } else {
        foreach ($rec in ($findings | Sort-Object StartLine)) {
            $endLine = $rec.StartLine + $rec.LineCount - 1
            if ($rec.Safe) {
                Write-Host "Lines $($rec.StartLine)-$endLine [auto-fixable]:"
                foreach ($l in $rec.Lines) { Write-Host "  before: $l" }
                Write-Host "  after:  $($rec.Text)"
            } else {
                Write-Host "Lines $($rec.StartLine)-$endLine [flagged: $($rec.Reason)]:"
                foreach ($l in $rec.Lines) { Write-Host "  $l" }
            }
            Write-Host ''
        }
    }
} else {
    Get-LintMarkdownFiles -PathOverride $PathOverride -VaultRootOverride $VaultRootOverride | ForEach-Object {
        $path = $_.FullName
        $f = Read-FileLines -Path $path
        $findings = Get-HardWrapFindings -Lines $f.Lines
        if ($findings.Count -eq 0) { return }

        $autoCount    = ($findings | Where-Object { $_.Safe } | Measure-Object -Property LineCount -Sum).Sum
        $flaggedCount = ($findings | Where-Object { -not $_.Safe } | Measure-Object -Property LineCount -Sum).Sum
        if (-not $autoCount) { $autoCount = 0 }
        if (-not $flaggedCount) { $flaggedCount = 0 }

        if ($Update) {
            if ($autoCount -gt 0) {
                Write-HardWrapFixes -Path $path -Lines $f.Lines -Findings $findings -Eol $f.Eol
                Write-Host "Updated: $($_.Name) ($autoCount line(s) joined)"
            }
        } else {
            Write-Host "$($_.Name)"
            if ($autoCount -gt 0) { Write-Host "  auto-fixable: $autoCount line(s)" }
            if ($flaggedCount -gt 0) { Write-Host "  flagged for review: $flaggedCount line(s)" }
        }
    }
}
