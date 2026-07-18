# vault-common.ps1
# Shared helpers for vault skill scripts.
# Dot-source this file from any skill script:
#   $_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
#   . (Join-Path $_skillDir '..' '_shared' 'vault-common.ps1')

# UTF-8 without BOM. The built-in [System.Text.Encoding]::UTF8 emits a BOM on write;
# most vault files have none, so always write with this instead.
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# Locate the vault root using a tiered strategy:
#   1. $env:CLAUDE_PROJECT_DIR — set by the skill harness; authoritative in skill context.
#   2. Walk up from $StartPath looking for a directory that contains .git.
#   3. Throw if neither succeeds.
# Returns the vault root with a trailing backslash.
function Get-VaultRoot {
    param(
        # Starting directory for the .git search; typically $PSScriptRoot of the calling script.
        [Parameter(Mandatory)][string]$StartPath
    )
    if ($env:CLAUDE_PROJECT_DIR -and (Test-Path (Join-Path $env:CLAUDE_PROJECT_DIR '.git'))) {
        return $env:CLAUDE_PROJECT_DIR.TrimEnd('\') + '\'
    }
    $dir = [System.IO.DirectoryInfo]::new((Resolve-Path $StartPath).Path)
    while ($null -ne $dir) {
        if (Test-Path (Join-Path $dir.FullName '.git')) {
            return $dir.FullName.TrimEnd('\') + '\'
        }
        $dir = $dir.Parent
    }
    throw "Vault root not found: CLAUDE_PROJECT_DIR is not set or has no .git, and no .git directory found above: $StartPath"
}

# Resolve a vault-relative path to an absolute path under $VaultRoot.
# An already-absolute path is returned unchanged. Returns $null for empty input.
function Resolve-VaultPath {
    param(
        # Vault root with trailing backslash, as returned by Get-VaultRoot.
        [Parameter(Mandatory)][string]$VaultRoot,
        # Vault-relative path to resolve. Absolute paths pass through unchanged. Empty returns $null.
        [string]$Path
    )
    if (-not $Path) { return $null }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $VaultRoot $Path)
}

# Enumerate *.md files under the vault with optional filtering.
function Get-VaultMarkdownFiles {
    param(
        # Vault root with trailing backslash, as returned by Get-VaultRoot.
        [Parameter(Mandatory)][string]$VaultRoot,
        # Vault-relative path to scan instead of the full vault. When set, IncludeFolders is
        # bypassed but ExcludeFiles/ExcludePaths still apply. Used by tests and ad-hoc runs.
        [string]$PathOverride,
        # Vault-relative folder names to scan (e.g. 'Areas', 'Projects'). When omitted and no
        # OverridePath is given, the full vault is scanned and dot-prefixed dirs are excluded.
        [string[]]$IncludeFolders,
        # Bare filenames to skip (e.g. 'Document-Conventions.md').
        [string[]]$ExcludeFiles,
        # Vault-relative directory paths whose contents are skipped entirely (including subfolders).
        [string[]]$ExcludePaths,
        # In full-scan mode (no PathOverride/IncludeFolders), also descend into dot-prefixed
        # directories (e.g. .claude, .myai) instead of skipping them. Default false preserves
        # existing full-scan behavior for callers that don't pass this switch.
        [switch]$IncludeHiddenFolders
    )

    $excludedFull = if ($ExcludePaths) { $ExcludePaths | ForEach-Object { (Join-Path $VaultRoot $_).TrimEnd('\') } } else { @() }

    $roots = if ($PathOverride) {
        @(Resolve-VaultPath -VaultRoot $VaultRoot -Path $PathOverride)
    } elseif ($IncludeFolders) {
        $IncludeFolders | ForEach-Object { Join-Path $VaultRoot $_ }
    } else {
        @($VaultRoot)
    }

    $fullScan = -not $PathOverride -and -not $IncludeFolders

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }

        Get-ChildItem -Path $root -Recurse -Filter '*.md' | Where-Object {
            # Full-scan mode: skip dot-prefixed directories (e.g. .claude, .myai) unless the
            # caller opted in to hidden folders.
            if ($fullScan -and -not $IncludeHiddenFolders) {
                $rel  = Split-Path $_.FullName.Substring($VaultRoot.Length) -Parent
                $segs = $rel -split '[/\\]'
                if ($segs | Where-Object { $_ -ne '' -and $_.StartsWith('.') }) { return $false }
            }
            if ($ExcludeFiles -and $ExcludeFiles -contains $_.Name) { return $false }
            foreach ($ex in $excludedFull) {
                if ($_.FullName -like "$ex\*") { return $false }
            }
            return $true
        }
    }
}

# Extract a YYYY-MM-DD date from a leading (YYYY-MM-DD-Title) or trailing (Title-YYYY-MM-DD)
# filename date segment. Returns $null when no such segment is present. Generic filename
# logic - has no dependency on frontmatter content.
function Get-FilenameDate {
    param(
        # Filename stem to inspect (no directory, no extension).
        [Parameter(Mandatory)][string]$BaseName
    )
    if ($BaseName -match '-(\d{4}-\d{2}-\d{2})$') { return $Matches[1] }
    if ($BaseName -match '^(\d{4}-\d{2}-\d{2})-') { return $Matches[1] }
    return $null
}

# True when $File is a folder note: its basename equals the name of its containing folder
# (e.g. Personal/Personal.md). Never reads file content.
function Test-IsFolderNote {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File
    )
    $parentName = Split-Path (Split-Path $File.FullName -Parent) -Leaf
    return $File.BaseName -eq $parentName
}

# True when $RelPath is a Guide doc: any file under .claude/guides/ (Vault-Guide.md,
# Document-Conventions.md, Vault-Organization.md, Skill-Dev.md, Frontmatter-Schema.md, and any
# future addition to that folder) - the vault's structural agent-guide docs, the backend's
# runtime-loaded guides tier. Path-based rather than parsed from the H1 "Filename.md -
# Description" heading, since that heading format is shared with folder notes (Test-IsFolderNote
# already excludes those separately) and isn't a reliable Guide-doc-specific signal on its own.
function Test-IsGuideDoc {
    param(
        [Parameter(Mandatory)][string]$RelPath
    )
    $relFwd = $RelPath -replace '\\', '/'
    return $relFwd -match '(^|/)\.claude/guides/'
}

# True when $RelPath is a Templater template doc: any file under Resources/Vault/Templates/.
# Path-based like Test-IsGuideDoc. Used by check-provenance.ps1's Checks 2/3 only - these
# files carry a leading Templater <%* ... %> script block before their `---` frontmatter
# fence, which Get-FrontmatterLines doesn't tolerate (it requires the file to start with
# `---`), so their real doc.created/doc.type fields read as missing. Not merged into
# Test-IsTemplaterScript, which is specifically for files with no markdown body at all.
function Test-IsTemplateDoc {
    param(
        [Parameter(Mandatory)][string]$RelPath
    )
    $relFwd = $RelPath -replace '\\', '/'
    return $relFwd -match '(^|/)Resources/Vault/Templates/'
}

# True when $Content, trimmed, is entirely a single Templater command block (<%* ... %>) with
# no markdown body around it - a pure insertable script (e.g. Resources/Vault/Templates/ADO-
# Link-Template.md), not an authored document. Content-based rather than path-based: most
# files under Templates/ are real markdown templates with real doc.* frontmatter (e.g.
# Meeting-Template.md) and must stay in scope, so excluding the whole folder would be wrong -
# only a file that is *entirely* script has no document to attach doc.* fields to.
function Test-IsTemplaterScript {
    param(
        [Parameter(Mandatory)][string]$Content
    )
    $trimmed = $Content.Trim()
    return $trimmed.StartsWith('<%*') -and $trimmed.EndsWith('%>')
}

# Normalize a path for comparison: forward slashes, no trailing slash, lowercased.
function ConvertTo-ComparablePath {
    param([string]$Path)
    return (($Path -replace '\\', '/').TrimEnd('/')).ToLowerInvariant()
}
