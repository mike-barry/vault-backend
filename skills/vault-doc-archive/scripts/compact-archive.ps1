# compact-archive.ps1
# On-demand Archive/ compaction: rolls flat files into YYYY-MM/ subfolders, then rolls
# prior-year YYYY-MM/ subfolders into YYYY/ subfolders.
#
# Usage:
#   pwsh -NonInteractive -NoProfile -File compact-archive.ps1 -ArchiveDir <vault-relative-path>
#   pwsh -NonInteractive -NoProfile -File compact-archive.ps1 -ArchiveDir <vault-relative-path> -WhatIf
#
# Date source: trailing (-YYYY-MM-DD) or leading (YYYY-MM-DD-) filename date if present;
#              falls back to the 'doc.archived' frontmatter field.
# Idempotent — safe to re-run.

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ArchiveDir,
    # Override the vault root; used by unit tests to redirect to a temporary worktree.
    [string]$VaultRootOverride
)

$ErrorActionPreference = 'Stop'

$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-common.ps1')
. (Join-Path $_skillDir '..' '_shared' 'vault-frontmatter.ps1')

$VaultRoot = if ($VaultRootOverride) { Format-VaultRoot $VaultRootOverride } `
             else { Get-VaultRoot -StartPath $PSScriptRoot }

function Get-FileDate {
    param([System.IO.FileInfo]$File)
    $fnDate = Get-FilenameDate -BaseName $File.BaseName
    if ($fnDate) { return $fnDate }
    # Frontmatter fallback
    $content = Get-Content -Path $File.FullName -Raw -Encoding UTF8
    return Get-FrontmatterField -Content $content -Field 'doc.archived'
}

$archiveFullPath = Resolve-VaultPath -VaultRoot $VaultRoot -Path $ArchiveDir
if (-not (Test-Path $archiveFullPath)) {
    Write-Error "Archive directory not found: $archiveFullPath"
    exit 1
}

$today       = Get-Date
$currentYM   = $today.ToString('yyyy-MM')
$currentYear = $today.Year
$movedMonth  = 0
$movedYear   = 0
$skipped     = 0

# ── Pass 1: month rollup ──────────────────────────────────────────────────────
# Flat *.md files in Archive/ from prior months → Archive/YYYY-MM/

$flatFiles = Get-ChildItem -Path $archiveFullPath -Filter '*.md' -File
foreach ($file in $flatFiles) {
    $dateStr = Get-FileDate $file
    if (-not $dateStr) {
        Write-Warning "No date found for '$($file.Name)' — skipping"
        $skipped++
        continue
    }
    $ym = $dateStr.Substring(0, 7)   # YYYY-MM
    if ($ym -ge $currentYM) { continue }   # current month — leave flat

    $destDir  = Join-Path $archiveFullPath $ym
    $destFile = Join-Path $destDir $file.Name

    if ($PSCmdlet.ShouldProcess($file.Name, "Move to $ym/")) {
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir | Out-Null
            Write-Host "  mkdir $ym/"
        }
        Move-Item -Path $file.FullName -Destination $destFile
        Write-Host "  $($file.Name) => $ym/$($file.Name)"
        $movedMonth++
    }
}

# ── Pass 2: year rollup ───────────────────────────────────────────────────────
# Files in Archive/YYYY-MM/ from prior years → Archive/YYYY/
# Then remove now-empty YYYY-MM/ subfolders.

$ymDirs = Get-ChildItem -Path $archiveFullPath -Directory |
          Where-Object { $_.Name -match '^\d{4}-\d{2}$' }

foreach ($ymDir in $ymDirs) {
    $year = [int]$ymDir.Name.Substring(0, 4)
    if ($year -ge $currentYear) { continue }   # current year — leave in YYYY-MM/

    $yearDir = Join-Path $archiveFullPath $year.ToString()
    $ymFiles = Get-ChildItem -Path $ymDir.FullName -Filter '*.md' -File

    foreach ($file in $ymFiles) {
        $destFile = Join-Path $yearDir $file.Name
        if ($PSCmdlet.ShouldProcess($file.Name, "Move to $year/")) {
            if (-not (Test-Path $yearDir)) {
                New-Item -ItemType Directory -Path $yearDir | Out-Null
                Write-Host "  mkdir $year/"
            }
            Move-Item -Path $file.FullName -Destination $destFile
            Write-Host "  $($ymDir.Name)/$($file.Name) => $year/$($file.Name)"
            $movedYear++
        }
    }

    # Remove empty YYYY-MM/ dir
    if (-not (Get-ChildItem -Path $ymDir.FullName)) {
        if ($PSCmdlet.ShouldProcess($ymDir.Name, 'Remove empty subfolder')) {
            Remove-Item -Path $ymDir.FullName
            Write-Host "  rmdir $($ymDir.Name)/ (empty)"
        }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host "Compaction complete: $movedMonth file(s) moved to month folders, $movedYear file(s) moved to year folders, $skipped skipped."
