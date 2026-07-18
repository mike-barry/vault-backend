# Detects markdown-format fragment links - [Text](#anchor) or [Text](Other-Note#anchor) -
# that Obsidian does not resolve as heading jumps (only wikilinks do: [[#Heading]] /
# [[Note#Heading]]). Verifies each fragment against the target file's actual headings and
# auto-fixes the unambiguous cases; anything it can't resolve on its own is reported for
# manual review rather than guessed.
#
# Scans the whole vault, including .claude/skills, since those docs suffer the same broken
# in-app navigation as ordinary notes. External links (http:, https:, mailto:, //, etc.) are
# never matched - the target-prefix character class excludes '#', so a link only matches here
# when nothing but a URI scheme could precede the fragment, and the scheme check below skips it.

param(
    # Apply auto-fixable rewrites to disk. Without this switch the script reports what would
    # change (and what still needs manual review) without modifying any files.
    [switch]$Update,
    # Vault-relative folder to scope the scan (e.g. 'Areas/Personal'). When omitted, the whole
    # vault is scanned, including dot-prefixed directories like .claude.
    [string]$PathOverride,
    # Vault root directory. Auto-resolved from the script location when not specified; pass
    # explicitly for non-default locations such as a test worktree.
    [string]$VaultRootOverride
)

. "$PSScriptRoot\lint-common.ps1"
$vaultRoot = if ($VaultRootOverride) { $VaultRootOverride } else { Get-VaultRoot $PSScriptRoot }

# Full vault scan (unless -PathOverride narrows it) with hidden folders included, so
# .claude/skills docs are covered - Get-LintMarkdownFiles's fixed include-folder list would
# exclude them entirely.
$files = @(Get-VaultMarkdownFiles -VaultRoot $vaultRoot -PathOverride $PathOverride `
    -ExcludeFiles $excludeFiles -ExcludePaths $excludePaths -IncludeHiddenFolders)

# Index every file by lowercase basename for the vault-wide fallback when a cross-file target
# doesn't resolve relative to the linking file's own directory.
$fileIndex = @{}
foreach ($f in $files) {
    $key = $f.BaseName.ToLowerInvariant()
    if (-not $fileIndex.ContainsKey($key)) {
        $fileIndex[$key] = New-Object 'System.Collections.Generic.List[string]'
    }
    $fileIndex[$key].Add($f.FullName)
}

$contentCache = @{}   # FullName -> raw content
$headingCache = @{}   # FullName -> slug -> List[heading text]

function ConvertTo-Slug {
    param([string]$Text)
    $s = $Text.ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9]+', '-')
    return $s.Trim('-')
}

function Get-CachedContent {
    param([string]$Path)
    if (-not $contentCache.ContainsKey($Path)) {
        $contentCache[$Path] = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    }
    return $contentCache[$Path]
}

function Get-CachedHeadingMap {
    param([string]$Path)
    if (-not $headingCache.ContainsKey($Path)) {
        $map = @{}
        $content = Get-CachedContent $Path
        foreach ($m in [regex]::Matches($content, '(?m)^#{1,6}[ \t]+(.+?)\s*$')) {
            $headingText = $m.Groups[1].Value.Trim()
            $slug = ConvertTo-Slug $headingText
            if (-not $map.ContainsKey($slug)) {
                $map[$slug] = New-Object 'System.Collections.Generic.List[string]'
            }
            [void]$map[$slug].Add($headingText)
        }
        $headingCache[$Path] = $map
    }
    return $headingCache[$Path]
}

# Resolve a cross-file link target to an absolute path: first relative to the linking file's
# own directory (with/without a .md extension, mirroring how a relative markdown link actually
# resolves in Obsidian), then falling back to a vault-wide basename search.
function Resolve-LinkTargetFile {
    param([string]$Target, [string]$SourceDir)
    $clean = $Target.Replace('\', '/').Trim()
    $candidates = if ($clean.ToLowerInvariant().EndsWith('.md')) {
        @((Join-Path $SourceDir $clean))
    } else {
        @((Join-Path $SourceDir "$clean.md"), (Join-Path $SourceDir $clean))
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) {
            return [PSCustomObject]@{ Status = 'found'; Path = (Resolve-Path -LiteralPath $c).Path }
        }
    }
    $lastSegment = ($clean -split '/')[-1]
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($lastSegment).ToLowerInvariant()
    if ($fileIndex.ContainsKey($baseName)) {
        $found = $fileIndex[$baseName]
        if ($found.Count -eq 1) { return [PSCustomObject]@{ Status = 'found'; Path = $found[0] } }
        return [PSCustomObject]@{ Status = 'ambiguous'; Count = $found.Count }
    }
    return [PSCustomObject]@{ Status = 'notfound' }
}

# Group 1 (display text) excludes '[' as well as ']' - real markdown link text never contains
# a literal, unescaped bracket, and excluding it stops a stray '[' elsewhere in the line (e.g.
# a literal `[[Target-Name` inside a code-span example) from swallowing everything up to some
# unrelated later '](...)' into one giant bogus match. Also excludes newlines so a match can
# never span multiple lines. Group 2 (target) excludes '#' so it can only capture the text
# before the first fragment marker - without that exclusion greedy backtracking could match a
# later '#' instead.
$linkPattern = '\[([^\[\]\r\n]*)\]\(([^)\s#]*)#([^)\s]+)\)'

$totalFixed = 0
$totalUnresolved = 0

foreach ($f in $files) {
    $path = $f.FullName
    $relPath = $path.Substring($vaultRoot.Length)
    $content = Get-CachedContent $path
    $sourceDir = Split-Path $path -Parent

    $fileFixLines    = @()
    $fileUnresolved  = @()
    $replacements    = @()   # Index, Length, Replacement - applied back-to-front

    foreach ($m in [regex]::Matches($content, $linkPattern)) {
        $display  = $m.Groups[1].Value
        $target   = $m.Groups[2].Value
        $fragment = $m.Groups[3].Value

        # External links (scheme or protocol-relative) are valid as-is - never flag these.
        if ($target -match '^[a-zA-Z][a-zA-Z0-9+.\-]*:' -or $target -match '^//') { continue }

        # Inline-code-quoted illustration (`` `[Text](#anchor)` ``) - a backtick immediately
        # touching both the opening '[' and the closing ')' means the whole expression is shown
        # as an example, not a live link. Docs like this skill's own SKILL.md and Lint-System.md
        # quote the broken syntax as prose; never flag those.
        $beforeChar = if ($m.Index -gt 0) { $content[$m.Index - 1] } else { $null }
        $afterIndex = $m.Index + $m.Length
        $afterChar  = if ($afterIndex -lt $content.Length) { $content[$afterIndex] } else { $null }
        if ($beforeChar -eq '`' -and $afterChar -eq '`') { continue }

        $isSamePage = [string]::IsNullOrEmpty($target)
        if ($isSamePage) {
            $targetPath = $path
        } else {
            $resolved = Resolve-LinkTargetFile -Target $target -SourceDir $sourceDir
            if ($resolved.Status -eq 'notfound') {
                $fileUnresolved += "  $($m.Value) -> target file not found: $target"
                $totalUnresolved++
                continue
            } elseif ($resolved.Status -eq 'ambiguous') {
                $fileUnresolved += "  $($m.Value) -> ambiguous target: $($resolved.Count) files named '$target' in vault"
                $totalUnresolved++
                continue
            }
            $targetPath = $resolved.Path
        }

        $headingMap = Get-CachedHeadingMap $targetPath
        $fragSlug = ConvertTo-Slug $fragment
        if (-not $headingMap.ContainsKey($fragSlug)) {
            $targetRel = $targetPath.Substring($vaultRoot.Length)
            $fileUnresolved += "  $($m.Value) -> no heading matches '#$fragment' in $targetRel"
            $totalUnresolved++
            continue
        }
        $candidates = $headingMap[$fragSlug]
        if ($candidates.Count -gt 1) {
            $fileUnresolved += "  $($m.Value) -> ambiguous heading: $($candidates.Count) headings match '#$fragment'"
            $totalUnresolved++
            continue
        }
        $headingText = $candidates[0]

        $displayTrim = $display.Trim()
        $sameText = [string]::Equals($displayTrim, $headingText, [System.StringComparison]::OrdinalIgnoreCase)
        $wikilink = if ($isSamePage) {
            if ($sameText) { "[[#$headingText]]" } else { "[[#$headingText|$displayTrim]]" }
        } else {
            $noteName = [System.IO.Path]::GetFileNameWithoutExtension($targetPath)
            if ($sameText) { "[[$noteName#$headingText]]" } else { "[[$noteName#$headingText|$displayTrim]]" }
        }

        $replacements += [PSCustomObject]@{ Index = $m.Index; Length = $m.Length; Replacement = $wikilink }
        $fileFixLines += "  $($m.Value)  ->  $wikilink"
        $totalFixed++
    }

    if ($replacements.Count -eq 0 -and $fileUnresolved.Count -eq 0) { continue }

    if ($Update -and $replacements.Count -gt 0) {
        $newContent = $content
        foreach ($r in ($replacements | Sort-Object Index -Descending)) {
            $newContent = $newContent.Substring(0, $r.Index) + $r.Replacement + $newContent.Substring($r.Index + $r.Length)
        }
        [System.IO.File]::WriteAllText($path, $newContent, $Utf8NoBom)
        Write-Host "Updated: $relPath ($($replacements.Count) link(s) fixed)"
    } elseif ($fileFixLines.Count -gt 0) {
        Write-Host "Would fix: $relPath"
        $fileFixLines | ForEach-Object { Write-Host $_ }
    }

    if ($fileUnresolved.Count -gt 0) {
        Write-Host "Needs manual review: $relPath"
        $fileUnresolved | ForEach-Object { Write-Host $_ }
    }
}

if ($totalFixed -eq 0 -and $totalUnresolved -eq 0) {
    Write-Host "No markdown-format anchor links found."
} else {
    Write-Host ""
    Write-Host "$totalFixed auto-fixable link(s), $totalUnresolved unresolved link(s) found."
}
