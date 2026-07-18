# vault-rename.ps1
# Renames or moves a vault markdown file and updates all wikilinks to it vault-wide.
# Defaults to report-only mode; pass -Update to apply changes.
#
# Usage:
#   .\vault-rename.ps1 -OldPath <vault-relative-path> -NewPath <vault-relative-path> [-Update] [-PathOverride <vault-relative-folder>] [-VaultRootOverride <absolute-path>]

param(
    [Parameter(Mandatory)][string]$OldPath,
    [Parameter(Mandatory)][string]$NewPath,
    [switch]$Update,
    [string]$PathOverride,
    [string]$VaultRootOverride
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

$vaultRoot = if ($VaultRootOverride) { $VaultRootOverride.TrimEnd('\') + '\' } else { Get-VaultRoot $PSScriptRoot }

$oldAbsolute = Join-Path $vaultRoot $OldPath
$newAbsolute = Join-Path $vaultRoot $NewPath

# Validate source
if (-not (Test-Path $oldAbsolute)) {
    Write-Error "OldPath does not exist: $OldPath"
    exit 1
}

if ((Get-Item $oldAbsolute).Extension -ne '.md') {
    Write-Error "OldPath is not a markdown file: $OldPath"
    exit 1
}

# Validate destination
if (Test-Path $newAbsolute) {
    Write-Error "NewPath already exists: $NewPath"
    exit 1
}

if ([System.IO.Path]::GetExtension($newAbsolute) -ne '.md') {
    Write-Error "NewPath must be a markdown file: $NewPath"
    exit 1
}

$oldBasename = [System.IO.Path]::GetFileNameWithoutExtension($oldAbsolute)
$newBasename = [System.IO.Path]::GetFileNameWithoutExtension($newAbsolute)

$pureMove = $oldBasename -eq $newBasename

# ---------------------------------------------------------------------------
# Vault-wide markdown file enumeration
# ---------------------------------------------------------------------------

# Hidden folders included so back-reference sweeps cover .claude (guides and skill docs
# carry wikilinks into vault content).
$vaultFiles = Get-VaultMarkdownFiles -VaultRoot $vaultRoot -PathOverride $PathOverride -IncludeHiddenFolders

# ---------------------------------------------------------------------------
# Uniqueness check (skip if pure folder move — no link text changes needed)
# ---------------------------------------------------------------------------

$ambiguous = $false

if (-not $pureMove) {
    $sameBasename = $vaultFiles | Where-Object {
        $_.FullName -ne $oldAbsolute -and
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $oldBasename
    }
    if ($sameBasename) {
        $ambiguous = $true
        Write-Warning "Ambiguous basename '$oldBasename' — also found in:"
        $sameBasename | ForEach-Object { Write-Warning "  $($_.FullName.Substring($vaultRoot.Length))" }
        Write-Warning "Bare [[${oldBasename}]] links will be skipped; only path-qualified links will be updated."
    }
}

# ---------------------------------------------------------------------------
# Grep pass — find all wikilinks referencing OldBasename
# ---------------------------------------------------------------------------

# Matches:
#   [[OldBasename]]
#   [[OldBasename#anchor]]
#   [[OldBasename|label]]
#   [[OldBasename#anchor|label]]
# Also path-qualified forms: [[Some/Path/OldBasename...]]
# Capture groups: (1) path prefix including slash, (2) anchor, (3) display text

$escapedBasename = [regex]::Escape($oldBasename)
$wikilinkPattern = [regex]"\[\[([^\[\]#|]*/)?(${escapedBasename})(#[^\]|]*)?(\|[^\]]+)?\]\]"

# Findings: list of hashtables with file, line index, old text, new text, status
$findings = [System.Collections.Generic.List[hashtable]]::new()

if (-not $pureMove) {
    foreach ($file in $vaultFiles) {
        $lines = [System.IO.File]::ReadAllLines($file.FullName)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $matches = $wikilinkPattern.Matches($line)
            foreach ($m in $matches) {
                $pathPrefix = $m.Groups[1].Value   # e.g. "Area/Inbox/" or ""
                $anchor     = $m.Groups[3].Value   # e.g. "#Section" or ""
                $display    = $m.Groups[4].Value   # e.g. "|Label" or ""
                $isBare     = $pathPrefix -eq ''

                if ($ambiguous -and $isBare) {
                    $findings.Add(@{
                        File      = $file.FullName.Substring($vaultRoot.Length)
                        Line      = $i + 1
                        OldText   = $m.Value
                        NewText   = $null
                        Status    = 'skip'
                        Reason    = 'ambiguous bare link'
                    })
                } else {
                    $newLink = "[[${pathPrefix}${newBasename}${anchor}${display}]]"
                    $findings.Add(@{
                        File      = $file.FullName.Substring($vaultRoot.Length)
                        Line      = $i + 1
                        OldText   = $m.Value
                        NewText   = $newLink
                        Status    = 'update'
                        Reason    = $null
                    })
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

$toUpdate = $findings | Where-Object { $_.Status -eq 'update' }
$toSkip   = $findings | Where-Object { $_.Status -eq 'skip' }

if ($pureMove) {
    Write-Host "Pure folder move — basename unchanged, no wikilink updates needed."
} else {
    if ($toUpdate) {
        Write-Host "`nWikilinks to update ($($toUpdate.Count)):"
        foreach ($f in $toUpdate) {
            Write-Host "  $($f.File):$($f.Line)"
            Write-Host "    $($f.OldText)  ->  $($f.NewText)"
        }
    } else {
        Write-Host "`nNo wikilinks found referencing '$oldBasename'."
    }

    if ($toSkip) {
        Write-Host "`nWikilinks skipped ($($toSkip.Count)):"
        foreach ($f in $toSkip) {
            Write-Host "  $($f.File):$($f.Line)  $($f.OldText)  [$($f.Reason)]"
        }
    }
}

Write-Host "`nFile: $OldPath  ->  $NewPath"

if (-not $Update) {
    Write-Host "`n[Report only] Pass -Update to apply changes."
    exit 0
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

# Group findings by file and apply all replacements in one pass per file
if (-not $pureMove -and $toUpdate) {
    $byFile = $toUpdate | Group-Object -Property File

    foreach ($group in $byFile) {
        $absPath = Join-Path $vaultRoot $group.Name
        $content = [System.IO.File]::ReadAllText($absPath)
        foreach ($f in $group.Group) {
            $content = $content.Replace($f.OldText, $f.NewText)
        }
        [System.IO.File]::WriteAllText($absPath, $content, $Utf8NoBom)
    }
}

# Create destination folder if needed (git mv requires the destination directory to exist)
$newDir = Split-Path $newAbsolute -Parent
if (-not (Test-Path $newDir)) {
    New-Item -ItemType Directory -Force -Path $newDir | Out-Null
}

$oldPathFwd = $OldPath.Replace('\', '/')
$newPathFwd = $NewPath.Replace('\', '/')

# git mv requires the source to be tracked. An untracked source makes git mv
# exit 128 ("not under version control"). Detect that case and fall back to a
# plain filesystem move + git add — there is no history to preserve, so this is
# equivalent and keeps the new path staged.
git -C $vaultRoot ls-files --error-unmatch -- $oldPathFwd 2>&1 | Out-Null
$isTracked = ($LASTEXITCODE -eq 0)

if ($isTracked) {
    git -C $vaultRoot mv $oldPathFwd $newPathFwd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git mv failed (exit $LASTEXITCODE)"
        exit 1
    }
} else {
    Move-Item -LiteralPath $oldAbsolute -Destination $newAbsolute
    git -C $vaultRoot add -- $newPathFwd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git add failed (exit $LASTEXITCODE) after moving untracked file"
        exit 1
    }
}

# Summary
$updatedCount     = if ($toUpdate) { $toUpdate.Count } else { 0 }
$updatedFileCount = if ($toUpdate) { ($toUpdate | Group-Object File).Count } else { 0 }
$skippedCount     = if ($toSkip)   { $toSkip.Count }   else { 0 }
Write-Host "`n[Applied]"
Write-Host "  File renamed: $OldPath -> $NewPath"
if ($pureMove) {
    Write-Host "  Wikilinks updated: 0 (pure folder move)"
} else {
    Write-Host "  Wikilinks updated: $updatedCount in $updatedFileCount file(s)"
    if ($toSkip) {
        Write-Host "  Wikilinks skipped: $skippedCount (ambiguous bare links — review manually)"
    }
}
