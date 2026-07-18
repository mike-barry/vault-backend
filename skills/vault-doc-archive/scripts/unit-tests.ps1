# unit-tests.ps1
# Test suite for compact-archive.ps1.
# Usage: pwsh .claude/skills/vault-doc-archive/scripts/unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')

$vaultRoot  = Get-VaultRoot $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'compact-archive.ps1'
$override   = '.vault-doc-archive-tests'

$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName $override
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot

# Invoke the script against a subfolder of the test root.
# $RelArchiveDir is relative to $testRoot (e.g. 'Archive').
# Extra args (e.g. '-WhatIf') go in $ExtraArgs.
function Invoke-Script {
    param(
        [string]$RelArchiveDir = 'Archive',
        [string[]]$ExtraArgs   = @()
    )
    $archiveVaultRel = "$override\$RelArchiveDir"
    $result = & pwsh -NonInteractive -NoProfile -File $scriptPath `
        -ArchiveDir $archiveVaultRel `
        -VaultRootOverride $worktreePath `
        @ExtraArgs *>&1
    return ($result | ForEach-Object { "$_" }) -join "`n"
}

# Create a test file inside the Archive subfolder of testRoot.
function New-ArchiveFile {
    param([string]$Name, [string]$Content = '')
    New-TestFile "Archive\$Name" $Content
}

try {

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

Write-Host "`n-- Validation --"

Run-Test 'Missing ArchiveDir exits with error' {
    $out = & pwsh -NonInteractive -NoProfile -File $scriptPath `
        -ArchiveDir "$override\NoSuchDir" `
        -VaultRootOverride $worktreePath *>&1 | Out-String
    $out -match 'not found'
}

# ---------------------------------------------------------------------------
# Date detection from filename
# ---------------------------------------------------------------------------

Write-Host "`n-- Date detection --"

Run-Test 'Trailing date detected: Title-YYYY-MM-DD.md moves to month folder' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile 'My-Note-2026-05-10.md'
    Invoke-Script | Out-Null
    (Assert-FileNotExists 'Archive\My-Note-2026-05-10.md') -and
    (Assert-FileExists    'Archive\2026-05\My-Note-2026-05-10.md')
}

Run-Test 'Leading date detected: YYYY-MM-DD-Title.md moves to month folder' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile '2026-05-10-My-Note.md'
    Invoke-Script | Out-Null
    (Assert-FileNotExists 'Archive\2026-05-10-My-Note.md') -and
    (Assert-FileExists    'Archive\2026-05\2026-05-10-My-Note.md')
}

Run-Test 'Frontmatter archived date used when filename has no date' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile 'Undated-Note.md' "---`ndoc.archived: 2026-05-01`n---`n# Body`n"
    Invoke-Script | Out-Null
    (Assert-FileNotExists 'Archive\Undated-Note.md') -and
    (Assert-FileExists    'Archive\2026-05\Undated-Note.md')
}

Run-Test 'File with no date is skipped with warning' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile 'Undated-Note.md' '# No date anywhere'
    $out = Invoke-Script
    (Assert-FileExists 'Archive\Undated-Note.md') -and   # still in place
    (Assert-OutputContains $out 'skipping')
}

# ---------------------------------------------------------------------------
# Month rollup
# ---------------------------------------------------------------------------

Write-Host "`n-- Month rollup --"

Run-Test 'File from current month stays flat' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    $today = (Get-Date).ToString('yyyy-MM-dd')
    New-ArchiveFile "Current-Note-$today.md"
    Invoke-Script | Out-Null
    Assert-FileExists "Archive\Current-Note-$today.md"
}

Run-Test 'YYYY-MM subfolder created when missing' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile 'Old-Note-2026-04-15.md'
    Invoke-Script | Out-Null
    Assert-FileExists 'Archive\2026-04\Old-Note-2026-04-15.md'
}

Run-Test 'Multiple files from different prior months sorted correctly' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile 'Note-2026-04-01.md'
    New-ArchiveFile 'Note-2026-05-01.md'
    Invoke-Script | Out-Null
    (Assert-FileExists 'Archive\2026-04\Note-2026-04-01.md') -and
    (Assert-FileExists 'Archive\2026-05\Note-2026-05-01.md')
}

Run-Test 'Existing YYYY-MM folder used without error' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive\2026-04') | Out-Null
    New-ArchiveFile 'Note-2026-04-01.md'
    $out = Invoke-Script
    (Assert-FileExists 'Archive\2026-04\Note-2026-04-01.md') -and
    (-not ($out -match 'error'))
}

# ---------------------------------------------------------------------------
# Year rollup
# ---------------------------------------------------------------------------

Write-Host "`n-- Year rollup --"

Run-Test 'File in prior-year YYYY-MM/ moves to YYYY/' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive\2025-03') | Out-Null
    New-TestFile "Archive\2025-03\Old-Plan.md"
    Invoke-Script | Out-Null
    (Assert-FileNotExists 'Archive\2025-03\Old-Plan.md') -and
    (Assert-FileExists    'Archive\2025\Old-Plan.md')
}

Run-Test 'Empty YYYY-MM/ removed after year rollup' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive\2025-03') | Out-Null
    New-TestFile "Archive\2025-03\Old-Plan.md"
    Invoke-Script | Out-Null
    Assert-FileNotExists 'Archive\2025-03'
}

Run-Test 'Non-empty YYYY-MM/ not removed when some files linger' {
    # Put a non-.md file in the month folder so it stays non-empty after rollup
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive\2025-03') | Out-Null
    New-TestFile "Archive\2025-03\Old-Plan.md"
    [System.IO.File]::WriteAllText(
        (Join-Path $testRoot 'Archive\2025-03\extra.txt'), 'keep', $Utf8NoBom)
    Invoke-Script | Out-Null
    # .md moved, folder still exists because extra.txt remains
    (Assert-FileExists 'Archive\2025\Old-Plan.md') -and
    (Test-Path (Join-Path $testRoot 'Archive\2025-03'))
}

Run-Test 'File in current-year YYYY-MM/ stays in YYYY-MM/' {
    $currentYM = (Get-Date).ToString('yyyy-MM')
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot "Archive\$currentYM") | Out-Null
    New-TestFile "Archive\$currentYM\Current-Plan.md"
    Invoke-Script | Out-Null
    Assert-FileExists "Archive\$currentYM\Current-Plan.md"
}

# ---------------------------------------------------------------------------
# WhatIf mode
# ---------------------------------------------------------------------------

Write-Host "`n-- WhatIf mode --"

Run-Test 'WhatIf: no files moved' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile 'Note-2026-04-01.md'
    Invoke-Script -ExtraArgs @('-WhatIf') | Out-Null
    Assert-FileExists 'Archive\Note-2026-04-01.md'   # still flat — nothing moved
}

Run-Test 'WhatIf: no folders created' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile 'Note-2026-04-01.md'
    Invoke-Script -ExtraArgs @('-WhatIf') | Out-Null
    Assert-FileNotExists 'Archive\2026-04'
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

Write-Host "`n-- Idempotency --"

Run-Test 'Running twice produces the same result' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile 'Note-2026-04-01.md'
    Invoke-Script | Out-Null
    $out = Invoke-Script   # second run
    # File already in 2026-04/ — no double-move, no error
    (Assert-FileExists 'Archive\2026-04\Note-2026-04-01.md') -and
    (-not ($out -match 'error'))
}

Run-Test 'Year rollup is idempotent' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive\2025-03') | Out-Null
    New-TestFile "Archive\2025-03\Old-Plan.md"
    Invoke-Script | Out-Null   # first run: 2025-03/ → 2025/
    $out = Invoke-Script       # second run: nothing to move
    (Assert-FileExists 'Archive\2025\Old-Plan.md') -and
    (-not ($out -match 'error'))
}

# ---------------------------------------------------------------------------
# Summary output
# ---------------------------------------------------------------------------

Write-Host "`n-- Summary output --"

Run-Test 'Summary line always printed' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    $out = Invoke-Script
    Assert-OutputContains $out 'Compaction complete'
}

Run-Test 'Summary counts match actual moves' {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'Archive') | Out-Null
    New-ArchiveFile 'Note-2026-04-01.md'
    New-ArchiveFile 'Note-2026-05-01.md'
    $out = Invoke-Script
    Assert-OutputContains $out '2 file(s) moved to month folders'
}

# ---------------------------------------------------------------------------
# recover-created-date.ps1
# ---------------------------------------------------------------------------

Write-Host "`nrecover-created-date.ps1"

# This script's recovery chain is git-history-dependent (falls back to `git log --follow
# --diff-filter=A`), so it needs real, dated commits rather than the shared worktree's
# untracked fixture files above. A fresh, isolated repo keeps that history independent of
# both the vault's own commit log and compact-archive.ps1's fixtures.
$recoverScript = Join-Path $PSScriptRoot 'recover-created-date.ps1'
$rcRoot = Join-Path ([System.IO.Path]::GetTempPath()) "vault-recover-date-test-$(Get-Random)"
New-Item -ItemType Directory -Path $rcRoot | Out-Null
git -C $rcRoot init -q 2>&1 | Out-Null
git -C $rcRoot config user.email test@test.com 2>&1 | Out-Null
git -C $rcRoot config user.name Test 2>&1 | Out-Null

function New-RcFile {
    param([string]$RelPath, [string]$Content = '')
    $abs = Join-Path $rcRoot $RelPath
    $dir = Split-Path $abs -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($abs, $Content, $Utf8NoBom)
}
function New-RcCommit {
    param([string]$Date, [string]$Message = 'test commit')
    git -C $rcRoot add -A 2>&1 | Out-Null
    $env:GIT_AUTHOR_DATE = "$Date 12:00:00"; $env:GIT_COMMITTER_DATE = "$Date 12:00:00"
    git -C $rcRoot commit -q -m $Message 2>&1 | Out-Null
    Remove-Item Env:\GIT_AUTHOR_DATE, Env:\GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
}
function Invoke-RecoverDate {
    param([string]$RelPath)
    (& pwsh -NoProfile -File $recoverScript -SourcePath $RelPath -VaultRootOverride $rcRoot 2>&1 | Out-String).Trim()
}

try {
    New-RcFile 'Existing-Created.md'          "---`ndoc.created: 1999-09-09`n---`n# X`n"
    New-RcFile 'Filename-Date-2021-02-02.md'  "# X`n"
    New-RcFile 'Git-Only.md'                  "# X`n"
    New-RcCommit -Date '2021-03-03' -Message 'add files'
    New-RcFile 'Unresolvable.md'              "# X`n"   # never committed

    $r1 = Invoke-RecoverDate 'Existing-Created.md'
    $r2 = Invoke-RecoverDate 'Filename-Date-2021-02-02.md'
    $r3 = Invoke-RecoverDate 'Git-Only.md'
    $r4 = Invoke-RecoverDate 'Unresolvable.md'

    Assert-That 'existing created frontmatter used as-is'  ($r1 -eq '1999-09-09') $r1
    Assert-That 'filename date segment used when present'  ($r2 -eq '2021-02-02') $r2
    Assert-That 'git first-add date used as last resort'   ($r3 -eq '2021-03-03') $r3
    Assert-That 'prints nothing when unresolvable'         ($r4 -eq '') $r4
} finally {
    Remove-Item -Recurse -Force $rcRoot -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# inject-provenance.ps1
# ---------------------------------------------------------------------------

Write-Host "`ninject-provenance.ps1"

$injectScript = Join-Path $PSScriptRoot 'inject-provenance.ps1'

# No git dependency (dates are passed in, not recovered) - the shared worktree's
# Run-Test/Reset-TestFolder pattern is fine here.
function Invoke-Inject {
    param([string]$RelPath, [string]$CreatedDate, [string]$ArchivedDate, [string]$Type = 'Note')
    $vaultRel = "$override\$RelPath"
    & pwsh -NoProfile -File $injectScript -SourcePath $vaultRel `
        -CreatedDate $CreatedDate -ArchivedDate $ArchivedDate -Type $Type -VaultRootOverride $worktreePath 2>&1 | Out-Null
}

Run-Test 'adds created, archived, and type to a file with no frontmatter' {
    New-TestFile 'Plain.md' "# Plain`n"
    Invoke-Inject 'Plain.md' '2026-01-01' '2026-02-01' 'Plan'
    $c = Get-TestFileContent 'Plain.md'
    $c.Contains('doc.created: 2026-01-01') -and $c.Contains('doc.archived: 2026-02-01') -and $c.Contains('doc.type: Plan')
}

Run-Test 'does not overwrite an existing created date' {
    New-TestFile 'HasCreated.md' "---`ndoc.created: 1999-01-01`n---`n# X`n"
    Invoke-Inject 'HasCreated.md' '2026-01-01' '2026-02-01'
    $c = Get-TestFileContent 'HasCreated.md'
    $c.Contains('doc.created: 1999-01-01') -and $c.Contains('doc.archived: 2026-02-01')
}

Run-Test 'archived is always overwritten' {
    New-TestFile 'HasArchived.md' "---`ndoc.archived: 1999-01-01`n---`n# X`n"
    Invoke-Inject 'HasArchived.md' '2026-01-01' '2026-02-01'
    $c = Get-TestFileContent 'HasArchived.md'
    $c.Contains('doc.archived: 2026-02-01') -and (-not $c.Contains('1999-01-01'))
}

Run-Test 'does not overwrite an existing type' {
    New-TestFile 'HasType.md' "---`ndoc.type: Idea`n---`n# X`n"
    Invoke-Inject 'HasType.md' '2026-01-01' '2026-02-01' 'Plan'
    $c = Get-TestFileContent 'HasType.md'
    $c.Contains('doc.type: Idea') -and (-not $c.Contains('doc.type: Plan'))
}

Run-Test 'preserves other existing frontmatter fields' {
    New-TestFile 'Other.md' "---`nfoo: bar`n---`n# X`n"
    Invoke-Inject 'Other.md' '2026-01-01' '2026-02-01' 'Plan'
    $c = Get-TestFileContent 'Other.md'
    $c.Contains('foo: bar') -and $c.Contains('doc.created: 2026-01-01') -and $c.Contains('doc.archived: 2026-02-01') -and $c.Contains('doc.type: Plan')
}

Run-Test 'writes no BOM' {
    New-TestFile 'Bom.md' "# X`n"
    Invoke-Inject 'Bom.md' '2026-01-01' '2026-02-01' 'Plan'
    Test-NoBom 'Bom.md'
}

Run-Test 'strips a use_skill entry and drops the empty agent.instructions key' {
    New-TestFile 'UseSkillOnly.md' "---`nagent.instructions:`n  - use_skill: `"vault-docs`"`n    when: `"editing this file`"`n---`n# X`n"
    Invoke-Inject 'UseSkillOnly.md' '2026-01-01' '2026-02-01' 'Plan'
    $c = Get-TestFileContent 'UseSkillOnly.md'
    (-not $c.Contains('use_skill')) -and (-not $c.Contains('agent.instructions'))
}

Run-Test 'strips use_skill but keeps bare and pinned entries' {
    New-TestFile 'MixedInstructions.md' "---`nagent.instructions:`n  - `"Load X when Y`"`n  - pinned: `"Never exfil this`"`n  - use_skill: `"vault-docs`"`n    when: `"editing this file`"`n---`n# X`n"
    Invoke-Inject 'MixedInstructions.md' '2026-01-01' '2026-02-01' 'Plan'
    $c = Get-TestFileContent 'MixedInstructions.md'
    (-not $c.Contains('use_skill')) -and $c.Contains('Load X when Y') -and $c.Contains('pinned: "Never exfil this"')
}

} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
