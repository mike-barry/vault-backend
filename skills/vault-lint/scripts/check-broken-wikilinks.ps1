param(
    # Vault-relative folder to scope the scan (e.g. 'Areas/Personal'). When omitted, all
    # configured include folders are scanned.
    [string]$PathOverride,
    # Vault root directory. Auto-resolved from the script location when not specified; pass
    # explicitly for non-default locations such as a test worktree.
    [string]$VaultRootOverride,
    # Path to the known-broken ignore list. Defaults to known-broken-wikilinks.txt under
    # .vault/state/vault-lint/; pass explicitly for tests or to use an alternate list.
    [string]$IgnoreFileOverride
)

. "$PSScriptRoot\lint-common.ps1"
$vaultRoot = if ($VaultRootOverride) { $VaultRootOverride } else { Get-VaultRoot $PSScriptRoot }

# Load the ignore list. Non-comment, non-blank lines before any [path:...] header are global
# ignores (suppressed everywhere). A [path:prefix] header starts a scoped section: names
# under it are suppressed only when the linking file's vault-relative path starts with that
# prefix. Matching is case-insensitive throughout.
$ignoreFile = if ($IgnoreFileOverride) {
    $IgnoreFileOverride
} else {
    Join-Path $vaultRoot '.vault\state\vault-lint\known-broken-wikilinks.txt'
}
$globalIgnoreSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$pathIgnores = @{}   # vault-relative prefix -> HashSet<string>
if (Test-Path $ignoreFile) {
    $currentPrefix = $null
    foreach ($line in [System.IO.File]::ReadAllLines($ignoreFile)) {
        if ($line -match '^\s*\[path:(.+)\]\s*$') {
            $currentPrefix = $Matches[1].Trim().Replace('\', '/').TrimEnd('/')
            if (-not $pathIgnores.ContainsKey($currentPrefix)) {
                $pathIgnores[$currentPrefix] = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            }
            continue
        }
        $entry = ($line -split '#', 2)[0].Trim()
        if (-not $entry) { continue }
        if ($null -eq $currentPrefix) {
            [void]$globalIgnoreSet.Add($entry)
        } else {
            [void]$pathIgnores[$currentPrefix].Add($entry)
        }
    }
}

function Test-IgnoredLink {
    param([string]$Target, [string]$RelPath)
    if ($globalIgnoreSet.Contains($Target)) { return $true }
    $normalizedRel = $RelPath.Replace('\', '/').TrimStart('/')
    foreach ($prefix in $pathIgnores.Keys) {
        if ($normalizedRel.StartsWith($prefix + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($pathIgnores[$prefix].Contains($Target)) { return $true }
        }
    }
    return $false
}

# Build index of all current notes (basename without extension). When scoped to an
# override path, only notes under that path count as existing (keeps tests hermetic). Includes
# .claude/skills docs - cross-file heading wikilinks can legitimately point there (see
# check-markdown-anchor-links.ps1), so a skill doc must count as an existing note like any other.
$indexRoot = if ($PathOverride) { Resolve-VaultPath -VaultRoot $vaultRoot -Path $PathOverride } else { $vaultRoot }
$currentNotes = @{}
# -Force so dot-prefixed folders (hidden on Linux/macOS without it) are indexed as on Windows.
Get-ChildItem -Path $indexRoot -Recurse -Force -Filter "*.md" | ForEach-Object {
    $currentNotes[$_.BaseName] = $true
}

# Build git history: renames (oldName -> newName) and deletes
$renameMap  = @{}
$deletedSet = @{}

$gitRenames = git -C $vaultRoot log --diff-filter=R --name-status --pretty=format: 2>$null |
    Where-Object { $_ -ne '' }
foreach ($line in $gitRenames) {
    if ($line -match '^R\d*\t(.+)\t(.+)$') {
        $oldName = [System.IO.Path]::GetFileNameWithoutExtension($Matches[1])
        $newName = [System.IO.Path]::GetFileNameWithoutExtension($Matches[2])
        if (-not $renameMap.ContainsKey($oldName)) {
            $renameMap[$oldName] = $newName
        }
    }
}

$gitDeletes = git -C $vaultRoot log --diff-filter=D --name-only --pretty=format: 2>$null |
    Where-Object { $_ -ne '' -and $_ -match '\.md$' }
foreach ($line in $gitDeletes) {
    $deletedSet[[System.IO.Path]::GetFileNameWithoutExtension($line)] = $true
}

# Scan for broken wiki-links
# Handles [[Note]], [[Note|Display]], [[Note#Anchor]], [[Folder/Note]]
# The (?<!!) lookbehind skips embeds/transclusions (e.g. ![[image.png]]), which
# often target images or PDFs rather than markdown notes.
$linkPattern = '(?<!!)\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]'
$broken = @()
$ignoredCount = 0

Get-LintMarkdownFiles -PathOverride $PathOverride -VaultRootOverride $vaultRoot | ForEach-Object {
    $path    = $_.FullName
    $relPath = $path.Substring($vaultRoot.Length)
    # ReadAllText with the standard UTF8 encoding accepts files with or without a BOM.
    # This is intentional for reads — we want to handle both. Only writes use $Utf8NoBom.
    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $scanContent = Remove-CodeSpansAndFences -Content $content

    foreach ($m in [regex]::Matches($scanContent, $linkPattern)) {
        $raw    = $m.Groups[1].Value.Trim()
        # Inside a markdown table the alias pipe must be escaped as `\|`, so the captured
        # target carries a trailing backslash ([[Note\|alias]] -> 'Note\'). Drop it before the
        # path split below, which would otherwise leave an empty target.
        $raw    = $raw.TrimEnd('\')
        # Strip path prefix if present (e.g. Folder/Note -> Note)
        $target = ($raw -split '[/\\]')[-1]

        if ($currentNotes.ContainsKey($target)) { continue }
        if (Test-IgnoredLink -Target $target -RelPath $relPath) { $ignoredCount++; continue }

        # A rename is only a usable remedy when the new name still exists. A file moved to
        # another folder and later deleted leaves a rename entry pointing at its own basename,
        # so without this check it would be reported as "renamed to itself".
        $renamedTo = if ($renameMap.ContainsKey($target)) { $renameMap[$target] } else { $null }
        $history = if ($renamedTo -and $currentNotes.ContainsKey($renamedTo)) {
            "was renamed to '$renamedTo'"
        } elseif ($deletedSet.ContainsKey($target) -or ($renamedTo -and $deletedSet.ContainsKey($renamedTo))) {
            "was deleted"
        } else {
            "no history found"
        }

        $broken += [PSCustomObject]@{ File = $relPath; Target = $target; History = $history }
    }
}

$ignoreNote = if ($ignoredCount -gt 0) { " ($ignoredCount ignored via known-broken list)" } else { "" }

if ($broken.Count -eq 0) {
    Write-Host "No broken wiki-links found.$ignoreNote"
} else {
    foreach ($b in $broken) {
        Write-Host "Broken: [[$($b.Target)]] in $($b.File)"
        Write-Host "  -> $($b.History)"
    }
    Write-Host ""
    Write-Host "$($broken.Count) broken wiki-link(s) found.$ignoreNote"
}
