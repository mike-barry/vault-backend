# unit-tests.ps1
# Test suite for vault-rename.ps1.
# Usage:  .\unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')

$vaultRoot  = Get-VaultRoot $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'vault-rename.ps1'
$override   = '.vault-doc-rename-tests'

$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName $override
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot

# Stage test files and invoke vault-rename.ps1 in the worktree.
# $ScriptArgs are forwarded as-is; -VaultRoot is always injected.
function Invoke-Script {
    param([string[]]$ScriptArgs)
    if ($ScriptArgs -contains '-Update') {
        git -C $worktreePath add $override 2>&1 | Out-Null
    }
    $result = & pwsh -NonInteractive -NoProfile -File $scriptPath @ScriptArgs -VaultRootOverride $worktreePath *>&1
    return ($result | ForEach-Object { "$_" }) -join "`n"
}

try {

# ---------------------------------------------------------------------------
# Validation tests (error paths)
# ---------------------------------------------------------------------------

Write-Host "`n-- Validation --"

Run-Test 'OldPath does not exist' {
    $out = Invoke-Script @('-OldPath', "$override\Missing.md", '-NewPath', "$override\New.md")
    Assert-OutputContains $out 'does not exist'
}

Run-Test 'OldPath is not a .md file' {
    New-TestFile 'Note.txt'
    $out = Invoke-Script @('-OldPath', "$override\Note.txt", '-NewPath', "$override\New.md")
    Assert-OutputContains $out 'not a markdown file'
}

Run-Test 'NewPath already exists' {
    New-TestFile 'Old.md'
    New-TestFile 'New.md'
    $out = Invoke-Script @('-OldPath', "$override\Old.md", '-NewPath', "$override\New.md")
    Assert-OutputContains $out 'already exists'
}

Run-Test 'NewPath is not a .md file' {
    New-TestFile 'Old.md'
    $out = Invoke-Script @('-OldPath', "$override\Old.md", '-NewPath', "$override\New.txt")
    Assert-OutputContains $out 'must be a markdown file'
}

# ---------------------------------------------------------------------------
# Report-only mode (no -Update)
# ---------------------------------------------------------------------------

Write-Host "`n-- Report-only mode --"

Run-Test 'Report mode does not rename file' {
    New-TestFile 'Alpha.md' 'some content'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override) | Out-Null
    (Assert-FileExists 'Alpha.md') -and (Assert-FileNotExists 'Beta.md')
}

Run-Test 'Report mode does not modify linking files' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' 'See [[Alpha]]'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override) | Out-Null
    Assert-FileContains 'Linker.md' '[[Alpha]]'
}

Run-Test 'Report output lists wikilinks to update' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' 'See [[Alpha]]'
    $out = Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override)
    (Assert-OutputContains $out '[[Alpha]]') -and (Assert-OutputContains $out '[[Beta]]')
}

# ---------------------------------------------------------------------------
# Simple rename (same folder)
# ---------------------------------------------------------------------------

Write-Host "`n-- Simple rename --"

Run-Test 'File is renamed' {
    New-TestFile 'Alpha.md'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileNotExists 'Alpha.md') -and (Assert-FileExists 'Beta.md')
}

Run-Test 'Bare [[OldName]] updated to [[NewName]]' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' 'See [[Alpha]]'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileContains 'Linker.md' '[[Beta]]') -and (Assert-FileNotContains 'Linker.md' '[[Alpha]]')
}

Run-Test 'Display text preserved: [[OldName|Label]] -> [[NewName|Label]]' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' 'See [[Alpha|the doc]]'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileContains 'Linker.md' '[[Beta|the doc]]') -and (Assert-FileNotContains 'Linker.md' '[[Alpha|')
}

Run-Test 'Anchor preserved: [[OldName#Section]] -> [[NewName#Section]]' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' 'See [[Alpha#Overview]]'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileContains 'Linker.md' '[[Beta#Overview]]') -and (Assert-FileNotContains 'Linker.md' '[[Alpha#')
}

Run-Test 'Anchor and display text preserved: [[OldName#Section|Label]] -> [[NewName#Section|Label]]' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' 'See [[Alpha#Overview|intro]]'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileContains 'Linker.md' '[[Beta#Overview|intro]]') -and (Assert-FileNotContains 'Linker.md' '[[Alpha#')
}

Run-Test 'Block ref anchor preserved: [[OldName#^blockref]] -> [[NewName#^blockref]]' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' 'See [[Alpha#^abc123]]'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileContains 'Linker.md' '[[Beta#^abc123]]') -and (Assert-FileNotContains 'Linker.md' '[[Alpha#')
}

Run-Test 'Multiple links in one file all updated' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' "First [[Alpha]], second [[Alpha|alias]], third [[Alpha#Sec]]"
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    $content = Get-TestFileContent 'Linker.md'
    ($content.Contains('[[Beta]]')) -and ($content.Contains('[[Beta|alias]]')) -and ($content.Contains('[[Beta#Sec]]')) -and (-not $content.Contains('[[Alpha'))
}

Run-Test 'Links in multiple files all updated' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker1.md' '[[Alpha]]'
    New-TestFile 'Linker2.md' '[[Alpha]]'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileContains 'Linker1.md' '[[Beta]]') -and (Assert-FileContains 'Linker2.md' '[[Beta]]')
}

Run-Test 'Unrelated links are not modified' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' 'See [[Alpha]] and [[Gamma]]'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileContains 'Linker.md' '[[Beta]]') -and (Assert-FileContains 'Linker.md' '[[Gamma]]') -and (Assert-FileNotContains 'Linker.md' '[[Alpha]]')
}

Run-Test 'No wikilinks referencing old name — file renamed cleanly' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Unrelated.md' 'Nothing here'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileNotExists 'Alpha.md') -and (Assert-FileExists 'Beta.md')
}

# ---------------------------------------------------------------------------
# Pure folder move (same basename, different folder)
# ---------------------------------------------------------------------------

Write-Host "`n-- Pure folder move --"

Run-Test 'File moved to subfolder' {
    New-TestFile 'Alpha.md'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Sub\Alpha.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileNotExists 'Alpha.md') -and (Assert-FileExists 'Sub\Alpha.md')
}

Run-Test 'Pure move creates destination folder if missing' {
    New-TestFile 'Alpha.md'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\NewFolder\Alpha.md", '-PathOverride', $override, '-Update') | Out-Null
    Assert-FileExists 'NewFolder\Alpha.md'
}

Run-Test 'Pure move does not alter wikilinks' {
    New-TestFile 'Alpha.md'
    New-TestFile 'Linker.md' '[[Alpha]]'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Sub\Alpha.md", '-PathOverride', $override, '-Update') | Out-Null
    Assert-FileContains 'Linker.md' '[[Alpha]]'
}

# ---------------------------------------------------------------------------
# Cross-folder rename (different folder AND different basename)
# ---------------------------------------------------------------------------

Write-Host "`n-- Cross-folder rename --"

Run-Test 'File moved and renamed, links updated' {
    New-TestFile 'Sub\Alpha.md'
    New-TestFile 'Linker.md' '[[Alpha]]'
    Invoke-Script @('-OldPath', "$override\Sub\Alpha.md", '-NewPath', "$override\Archive\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileExists 'Archive\Beta.md') -and (Assert-FileContains 'Linker.md' '[[Beta]]')
}

Run-Test 'Destination folder created when missing' {
    New-TestFile 'Alpha.md'
    Invoke-Script @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Nonexistent\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    Assert-FileExists 'Nonexistent\Beta.md'
}

# ---------------------------------------------------------------------------
# Ambiguous basename
# ---------------------------------------------------------------------------

Write-Host "`n-- Ambiguous basename --"

Run-Test 'Bare links skipped when basename is ambiguous' {
    New-TestFile 'Sub1\Alpha.md'
    New-TestFile 'Sub2\Alpha.md'   # duplicate basename — triggers ambiguity
    New-TestFile 'Linker.md' '[[Alpha]]'
    Invoke-Script @('-OldPath', "$override\Sub1\Alpha.md", '-NewPath', "$override\Sub1\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    (Assert-FileNotExists 'Sub1\Alpha.md') -and (Assert-FileExists 'Sub1\Beta.md') -and (Assert-FileContains 'Linker.md' '[[Alpha]]')   # rename happened; bare link preserved (skipped)
}

Run-Test 'Path-qualified links updated even when ambiguous' {
    New-TestFile 'Sub1\Alpha.md'
    New-TestFile 'Sub2\Alpha.md'
    New-TestFile 'Linker.md' "[[.vault-doc-rename-tests/Sub1/Alpha]]"
    Invoke-Script @('-OldPath', "$override\Sub1\Alpha.md", '-NewPath', "$override\Sub1\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    Assert-FileContains 'Linker.md' '[[.vault-doc-rename-tests/Sub1/Beta]]'
}

Run-Test 'Ambiguity warning printed in output' {
    New-TestFile 'Sub1\Alpha.md'
    New-TestFile 'Sub2\Alpha.md'
    $out = Invoke-Script @('-OldPath', "$override\Sub1\Alpha.md", '-NewPath', "$override\Sub1\Beta.md", '-PathOverride', $override)
    Assert-OutputContains $out 'Ambiguous'
}

# ---------------------------------------------------------------------------
# Untracked source file (git mv would exit 128 — must fall back to fs move + add)
# ---------------------------------------------------------------------------

Write-Host "`n-- Untracked source --"

# Invoke the script directly (bypassing Invoke-Script's auto-staging) so the
# source remains untracked.
function Invoke-ScriptNoStage {
    param([string[]]$ScriptArgs)
    $result = & pwsh -NonInteractive -NoProfile -File $scriptPath @ScriptArgs -VaultRootOverride $worktreePath *>&1
    return ($result | ForEach-Object { "$_" }) -join "`n"
}

Run-Test 'Untracked file is renamed without error' {
    New-TestFile 'Alpha.md'   # created but never git add-ed
    $out = Invoke-ScriptNoStage @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update')
    (Assert-FileNotExists 'Alpha.md') -and (Assert-FileExists 'Beta.md') -and (Assert-OutputContains $out 'Applied')
}

Run-Test 'Untracked rename stages the new path as an addition' {
    New-TestFile 'Alpha.md'
    Invoke-ScriptNoStage @('-OldPath', "$override\Alpha.md", '-NewPath', "$override\Beta.md", '-PathOverride', $override, '-Update') | Out-Null
    $status = (git -C $worktreePath status --porcelain -- "$override/Beta.md") -join "`n"
    $status -match '^A'   # staged addition
}

# ---------------------------------------------------------------------------
# Git history preservation
# ---------------------------------------------------------------------------
# Uses a dedicated subfolder alongside $testRoot (not inside it) so commits
# don't interfere with Reset-TestFolder. The worktree is temporary so
# commits here are discarded when the worktree is removed.

Write-Host "`n-- Git history preservation --"

$histDir    = '.vault-rename-hist-test'
$histDirAbs = Join-Path $worktreePath $histDir
New-Item -ItemType Directory -Force -Path $histDirAbs | Out-Null

# Create and commit a file so it has history to follow
[System.IO.File]::WriteAllText((Join-Path $histDirAbs 'Original.md'), 'initial content', $Utf8NoBom)
git -C $worktreePath add "$histDir/Original.md" 2>&1 | Out-Null
git -C $worktreePath -c commit.gpgsign=false commit -m 'hist-test: add Original.md' 2>&1 | Out-Null

# Rename the committed file via vault-rename
& pwsh -NonInteractive -NoProfile -File $scriptPath `
    -OldPath "$histDir\Original.md" -NewPath "$histDir\Renamed.md" `
    -PathOverride $histDir -VaultRootOverride $worktreePath -Update 2>&1 | Out-Null

Write-Host "  Rename is staged as a git rename, not delete+add" -NoNewline
$diffStatus = (git -C $worktreePath diff --cached --name-status) -join "`n"
if ($diffStatus -match '^R') {
    Write-Host '  PASS' -ForegroundColor Green
    $script:passed++
} else {
    Write-Host ''
    Write-Host "  FAIL: expected rename (R...) in staged diff, got:`n$diffStatus" -ForegroundColor Red
    $script:failed++
}

# Commit the rename so git log --follow can traverse it
git -C $worktreePath -c commit.gpgsign=false commit -m 'hist-test: rename to Renamed.md' 2>&1 | Out-Null

Write-Host "  git log --follow shows history through rename" -NoNewline
$followLog = (git -C $worktreePath log --follow --oneline "$histDir/Renamed.md") -join "`n"
if ($followLog -match 'hist-test: add Original\.md') {
    Write-Host '  PASS' -ForegroundColor Green
    $script:passed++
} else {
    Write-Host ''
    Write-Host "  FAIL: follow log missing original commit. Got:`n$followLog" -ForegroundColor Red
    $script:failed++
}

} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
