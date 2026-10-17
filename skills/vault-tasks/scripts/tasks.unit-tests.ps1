# tasks.unit-tests.ps1
# Test suite for tasks.ps1. Every case runs the script in a child pwsh against fixtures in a
# throwaway git worktree (Initialize-TestWorktree / Run-Test), passing -VaultRootOverride.
# Write verbs are checked by comparing the whole file to the exact expected text, so any
# change to an untouched line fails the test.
# Usage: pwsh -NoProfile -File .claude/skills/vault-tasks/scripts/tasks.unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')

[Console]::OutputEncoding = $Utf8NoBom

$vaultRoot  = Get-VaultRoot $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'tasks.ps1'
$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName '.vault-tasks-verb-tests'
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot
$sep   = [System.IO.Path]::DirectorySeparatorChar
$today = (Get-Date).ToString('yyyy-MM-dd')
function DaysAgo([int]$n) { (Get-Date).Date.AddDays(-$n).ToString('yyyy-MM-dd') }

# Run tasks.ps1 in a child pwsh. $P maps parameter name -> value (array, string, or $true
# for a switch). Returns @{ Code; Out; Err; Json }.
function Invoke-Tasks([string]$Action, [hashtable]$P = @{}) {
    $q = { param($s) "'" + ("$s" -replace "'", "''") + "'" }
    $parts = @("& $(& $q $scriptPath) -Action $Action -VaultRootOverride $(& $q $testRoot)")
    foreach ($k in $P.Keys) {
        $v = $P[$k]
        if ($v -is [bool]) { if ($v) { $parts += "-$k" }; continue }
        if ($v -is [array]) { $parts += "-$k " + (@($v | ForEach-Object { & $q $_ }) -join ',') }
        else { $parts += "-$k $(& $q $v)" }
    }
    $cmd = '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); ' + ($parts -join ' ') + '; exit $LASTEXITCODE'
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
    $errFile = Join-Path ([System.IO.Path]::GetTempPath()) "tasks-unit-err-$PID.txt"
    $out = & pwsh -NoProfile -NonInteractive -EncodedCommand $enc 2> $errFile
    $code = $LASTEXITCODE
    $err = if (Test-Path $errFile) { ([System.IO.File]::ReadAllText($errFile)).Trim() } else { '' }
    Remove-Item $errFile -ErrorAction SilentlyContinue
    $text = (@($out) | ForEach-Object { "$_" }) -join "`n"
    $json = $null
    if ($code -eq 0 -and $text) { $json = $text | ConvertFrom-Json -NoEnumerate }
    return @{ Code = $code; Out = $text; Err = $err; Json = $json }
}

# Run tasks.ps1 the way the skill and the git hook do: 'pwsh -File' with plain string
# arguments (no PowerShell array syntax). Returns the same shape as Invoke-Tasks.
function Invoke-TasksFile([string]$Action, [string[]]$ArgList = @()) {
    $errFile = Join-Path ([System.IO.Path]::GetTempPath()) "tasks-unit-err-$PID.txt"
    $out = & pwsh -NoProfile -NonInteractive -File $scriptPath -Action $Action -VaultRootOverride $testRoot @ArgList 2> $errFile
    $code = $LASTEXITCODE
    $err = if (Test-Path $errFile) { ([System.IO.File]::ReadAllText($errFile)).Trim() } else { '' }
    Remove-Item $errFile -ErrorAction SilentlyContinue
    $text = (@($out) | ForEach-Object { "$_" }) -join "`n"
    $json = $null
    if ($code -eq 0 -and $text) { $json = $text | ConvertFrom-Json -NoEnumerate }
    return @{ Code = $code; Out = $text; Err = $err; Json = $json }
}

# Per-test failure collector: Expect records a failed check; a Run-Test body ends with Ok.
$script:bad = $false
function Expect([bool]$Cond, [string]$What) {
    if (-not $Cond) { Write-Host "`n    FAIL: $What" -ForegroundColor Red; $script:bad = $true }
}
function Ok { $r = -not $script:bad; $script:bad = $false; return $r }

function Text([string[]]$Lines, [string]$Eol = "`n") { ($Lines -join $Eol) + $Eol }
function Expect-File([string]$Rel, [string]$Expected) {
    $got = Get-TestFileContent $Rel
    Expect ($got -ceq $Expected) "file $Rel differs:`n--- expected`n$Expected--- got`n$got---"
}
function Expect-Error($R, [string]$Pattern) {
    Expect ($R.Code -eq 1) "expected exit 1, got $($R.Code) (out: $($R.Out))"
    Expect ($R.Out -eq '') "expected no stdout on error, got: $($R.Out)"
    Expect ($R.Err -match $Pattern) "stderr '$($R.Err)' does not match '$Pattern'"
}

# ---- Fixtures --------------------------------------------------------------
# A: frontmatter, blank-separated items, children, a reminder, an Inbox/ folder.
$A = @(
    '---'
    'scope: personal'
    '---'
    '# A Tasks'
    ''
    '## 🔔 Reminders'
    ''
    '- Remind one'
    ''
    '## 🔥 Current'
    ''
    '- [ ] **Alpha** - first | 🆔 1 ➕ 2026-01-01'
    '    - alpha child'
    ''
    '- [/] Beta #group/x | 📅 2026-02-01 🆔 2 ➕ 2026-01-02'
    ''
    '## 🧱 Blocked'
    ''
    '## 📋 Backlog'
    ''
    '- [ ] Gamma #home | ⏫ 🆔 3 ➕ 2026-01-03'
    ''
    '## 🗺️ Side Quests'
    ''
    '## ✅ Done'
    ''
    '- [x] Old done | 🆔 4 ➕ 2026-01-01 ✅ 2026-01-05'
)
# B: no frontmatter, compact items (no blank lines), heading directly followed by an item.
$B = @(
    '# P Tasks'
    ''
    '## 🔥 Current'
    '- [ ] One | 🆔 10 ➕ 2026-01-01'
    '- [ ] Two | 🆔 11 ➕ 2026-01-01'
    '## 📋 Backlog'
    ''
    '## ✅ Done'
)
$ARel = 'Areas/A/Tasks.md'
$BRel = 'Projects/P/Tasks.md'
function Set-Fixtures {
    New-TestFile $ARel (Text $A)
    New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'Areas' 'A' 'Inbox') | Out-Null
    New-TestFile $BRel (Text $B)
}
# $Lines with index $At (0-based) replaced by $With (array; empty removes).
function Splice([string[]]$Lines, [int]$At, [int]$Remove, [string[]]$With = @()) {
    $l = [System.Collections.Generic.List[string]]::new([string[]]$Lines)
    $l.RemoveRange($At, $Remove)
    $l.InsertRange($At, $With)
    return [string[]]$l.ToArray()
}

try {

# ===========================================================================
Write-Host "`n-- list --"

Run-Test 'list: whole repo, file order, object shape' {
    Set-Fixtures
    $r = Invoke-Tasks 'list'
    $ids = @($r.Json | ForEach-Object { $_.Id }) -join ','
    Expect ($r.Code -eq 0) "exit $($r.Code): $($r.Err)"
    Expect ($ids -eq '1,2,3,4,10,11') "ids $ids"
    $a = @($r.Json)[0]
    $props = @($a.PSObject.Properties.Name) -join ','
    Expect ($props -eq 'Id,IdNumber,File,LineNumber,Section,Status,Symbol,Title,Text,Tags,Link,Promoted,Priority,Start,Scheduled,Due,Created,DoneDate,CancelledDate,Extra,Children,Raw') $props
    Expect ($a.File -eq $ARel -and $a.LineNumber -eq 12 -and $a.Section -eq 'Current' -and $a.Title -eq 'Alpha' -and $a.Text -eq 'first') "alpha $($a | ConvertTo-Json -Compress)"
    Expect ($a.Children -is [array] -and $a.Children.Count -eq 1 -and $a.Children[0] -eq '    - alpha child') 'children'
    Expect ($a.Tags -is [array] -and $a.Tags.Count -eq 0 -and $a.Extra -is [array]) 'empty arrays'
    Expect ($r.Out -match '"Tags": \[\]' -and $r.Out -match '"Children": \[\s*"    - alpha child"\s*\]') 'raw JSON arrays'
    $b = @($r.Json)[1]
    Expect ($b.Tags.Count -eq 1 -and $b.Tags[0] -eq 'group/x' -and $b.Status -eq 'in-progress' -and $b.Due -eq '2026-02-01') 'beta'
    Ok
}

Run-Test 'list: -Path folder, -Path file (either separator, absolute)' {
    Set-Fixtures
    $f = Invoke-Tasks 'list' @{ Path = 'Projects' }
    $g = Invoke-Tasks 'list' @{ Path = 'Areas\A\Tasks.md' }
    $h = Invoke-Tasks 'list' @{ Path = (Join-Path $testRoot 'Areas' 'A') }
    Expect ((@($f.Json | ForEach-Object Id) -join ',') -eq '10,11') "folder: $($f.Out)"
    Expect ((@($g.Json | ForEach-Object Id) -join ',') -eq '1,2,3,4') "file: $($g.Out) $($g.Err)"
    Expect ((@($h.Json | ForEach-Object Id) -join ',') -eq '1,2,3,4') "absolute: $($h.Err)"
    Ok
}

Run-Test 'list: -Section, -Status, -Tag, -Id filters' {
    Set-Fixtures
    $s = Invoke-Tasks 'list' @{ Section = @('Current', 'done') }
    $st = Invoke-Tasks 'list' @{ Status = 'in-progress' }
    $t = Invoke-Tasks 'list' @{ Tag = @('#HOME', 'nope') }
    $i = Invoke-Tasks 'list' @{ Id = @(3, 11) }
    $one = Invoke-Tasks 'list' @{ Id = 2 }
    Expect ((@($s.Json | ForEach-Object Id) -join ',') -eq '1,2,4,10,11') "section: $($s.Out)"
    Expect ((@($st.Json | ForEach-Object Id) -join ',') -eq '2') 'status'
    Expect ((@($t.Json | ForEach-Object Id) -join ',') -eq '3') 'tag'
    Expect ((@($i.Json | ForEach-Object Id) -join ',') -eq '3,11') 'id'
    Expect ($one.Out.TrimStart().StartsWith('[')) "single result is still an array: $($one.Out)"
    Ok
}

Run-Test 'list: empty result is [] ; bad filter values error' {
    Set-Fixtures
    $r = Invoke-Tasks 'list' @{ Tag = 'missing' }
    Expect ($r.Code -eq 0 -and $r.Out.Trim() -eq '[]') "out: $($r.Out)"
    Expect-Error (Invoke-Tasks 'list' @{ Section = 'Nope' }) "^Unknown section 'Nope'\. Use one of: Current, Blocked, Backlog, SideQuests, Done, Reminders$"
    Expect-Error (Invoke-Tasks 'list' @{ Status = 'started' }) "^Unknown status 'started'\. Use one of: todo, in-progress, done, cancelled$"
    Expect-Error (Invoke-Tasks 'list' @{ Path = 'No/Such' }) '^Path not found: No/Such$'
    Ok
}

Run-Test 'list: Archive folders are skipped' {
    Set-Fixtures
    New-TestFile 'Archive/Old/Tasks.md' (Text @('## 🔥 Current', '', '- [ ] Archived | 🆔 50'))
    $r = Invoke-Tasks 'list'
    Expect (-not (@($r.Json | ForEach-Object Id) -contains '50')) 'archived task listed'
    Ok
}

# ===========================================================================
Write-Host "`n-- check --"

Run-Test 'check: every code, plan links ignored, exit 0' {
    New-TestFile 'Areas/C/Tasks.md' (Text @(
        '## 🔔 Reminders'
        '- [ ] Checkbox reminder'
        '## 🔥 Active'
        '- [ ] No id no created'
        '- [ ] Has id | 🆔 5'
        '- [ ] | 🆔 6 ➕ 2026-01-01'
        '## Notes'
        '- [ ] ignored'
        '## 📋 Backlog'
        '- [ ] [[Task-7-Missing-Doc]] | 🆔 7 ➕ 2026-01-01'
        '- [ ] [[Task-8-Present]] | 🆔 8 ➕ 2026-01-01'
        '- [ ] [[Plan-Something]] - plan link | 🆔 9 ➕ 2026-01-01'
        '- [ ] Dup here | 🆔 5 ➕ 2026-01-01'
    ))
    New-TestFile 'Areas/C/Inbox/Task-8-Present.md' "# Present`n"
    New-TestFile 'Areas/C/Inbox/Task-30-Orphan.md' "# Orphan`n"
    New-TestFile 'Areas/C/Archive/Task-31-Archived.md' "# Archived`n"
    $r = Invoke-Tasks 'check'
    Expect ($r.Code -eq 0) "exit $($r.Code) $($r.Err)"
    $got = @($r.Json | ForEach-Object { "$($_.LineNumber):$($_.Code)" }) -join ' '
    $want = '2:CheckboxInReminders 3:LegacyHeading 4:MissingId 4:MissingCreated 5:MissingCreated 5:DuplicateId 6:EmptyTitle 7:UnknownSection 10:MissingDoc 13:DuplicateId :OrphanDoc'
    Expect ($got -eq $want) "got  $got`n    want $want"
    $orph = @($r.Json | Where-Object Code -eq 'OrphanDoc')[0]
    Expect ($orph.File -eq 'Areas/C/Inbox/Task-30-Orphan.md' -and $null -eq $orph.LineNumber -and $orph.Message -eq 'Task doc Task-30-Orphan.md has no task line with ID 30') "orphan $($orph | ConvertTo-Json -Compress)"
    $dup = @($r.Json | Where-Object Code -eq 'DuplicateId')[0]
    Expect ($dup.Message -eq 'ID 5 is also used at Areas/C/Tasks.md:13') $dup.Message
    $md = @($r.Json | Where-Object Code -eq 'MissingDoc')[0]
    Expect ($md.Message -eq 'Linked task doc Task-7-Missing-Doc.md not found' -and $md.File -eq 'Areas/C/Tasks.md') $md.Message
    Expect (@($r.Json | Where-Object { $_.LineNumber -eq 12 }).Count -eq 0) 'plan link flagged'
    Ok
}

Run-Test 'check: a Sprint heading is a legacy name for Current' {
    New-TestFile 'Tasks.md' (Text @('## 🔥 Sprint', '- [ ] a | 🆔 1 ➕ 2026-01-01'))
    $r = Invoke-Tasks 'check'
    $got = @($r.Json | ForEach-Object { "$($_.LineNumber):$($_.Code)" }) -join ' '
    Expect ($r.Code -eq 0 -and $got -eq '1:LegacyHeading') "got $got"
    Expect (@($r.Json)[0].Message -eq "Section '## 🔥 Sprint' uses the legacy name Sprint; rename it to Current") @($r.Json)[0].Message
    $l = Invoke-Tasks 'list'
    Expect (@($l.Json)[0].Section -eq 'Current') "section $(@($l.Json)[0].Section)"
    Ok
}

Run-Test 'check: DoneOutsideDone for [x]/[-] outside Done; [/] valid in any non-Done section' {
    New-TestFile 'Tasks.md' (Text @(
        '## 🔥 Current'
        '- [x] done in current | 🆔 1 ➕ 2026-01-01 ✅ 2026-01-02'
        '## 📋 Backlog'
        '- [/] started in backlog | 🆔 2 ➕ 2026-01-01'
        '- [-] cancelled in backlog | 🆔 3 ➕ 2026-01-01 ❌ 2026-01-02'
        '## 🗺️ Side Quests'
        '- [/] started side quest | 🆔 4 ➕ 2026-01-01'
        '## ✅ Done'
        '- [x] fine | 🆔 5 ➕ 2026-01-01 ✅ 2026-01-02'
    ))
    $r = Invoke-Tasks 'check'
    $got = @($r.Json | ForEach-Object { "$($_.LineNumber):$($_.Code)" }) -join ' '
    Expect ($r.Code -eq 0 -and $got -eq '2:DoneOutsideDone 5:DoneOutsideDone') "got $got"
    Expect (@($r.Json)[0].Message -eq 'A done task is in section Current; only Done holds [x] and [-]') @($r.Json)[0].Message
    Ok
}

Run-Test 'add/update: cannot put an open task in Done or a done task outside it' {
    Set-Fixtures
    Expect-Error (Invoke-Tasks 'add' @{ Path = $ARel; Title = 'x'; Section = 'Done' }) '^Use -Action done or -Action cancel to put a task in Done; add takes Current, Blocked, Backlog, SideQuests, or Reminders$'
    Expect-Error (Invoke-Tasks 'update' @{ Id = 4; Section = 'Backlog' }) '^Task 4 is done; pass -Status todo or in-progress to move it out of Done$'
    Expect-File $ARel (Text $A)
    $r = Invoke-Tasks 'update' @{ Id = 4; Section = 'Backlog'; Status = 'todo' }
    Expect ($r.Code -eq 0 -and $r.Json.Status -eq 'todo' -and $null -eq $r.Json.DoneDate -and $r.Json.Section -eq 'Backlog') "$($r.Out) $($r.Err)"
    Ok
}

Run-Test 'check: clean file gives [] ; -Path scopes problems and orphans' {
    Set-Fixtures
    New-TestFile 'Areas/Z/Tasks.md' (Text @('## 🔥 Current', '- [ ] no id'))
    New-TestFile 'Areas/Z/Task-99-Orphan.md' "# x`n"
    $a = Invoke-Tasks 'check' @{ Path = 'Areas/A' }
    $z = Invoke-Tasks 'check' @{ Path = 'Areas/Z/Tasks.md' }
    Expect ($a.Code -eq 0 -and $a.Out.Trim() -eq '[]') "A: $($a.Out)"
    Expect ((@($z.Json | ForEach-Object Code) -join ',') -eq 'MissingId,MissingCreated,OrphanDoc') "Z: $($z.Out)"
    Ok
}

# ===========================================================================
Write-Host "`n-- groups --"

# Two files: alpha in both (one done), beta in G1 only, beta-two (a name extending beta) in G2.
function Set-GroupFixtures {
    New-TestFile 'Areas/G1/Tasks.md' (Text @(
        '## 🔥 Current'
        '- [ ] a #group/beta | 🆔 1 ➕ 2026-01-01'
        '- [/] b #home #group/alpha #group/alpha | 🆔 2 ➕ 2026-01-01'
        '## ✅ Done'
        '- [x] c #group/alpha | 🆔 3 ➕ 2026-01-01 ✅ 2026-01-02'
    ))
    New-TestFile 'Projects/G2/Tasks.md' (Text @(
        '## 🔥 Current'
        '- [ ] d #group/alpha | 🆔 4 ➕ 2026-01-01'
        '- [ ] e #group/beta-two | 🆔 5 ➕ 2026-01-01'
    ))
}
function Set-ViewFixtures {
    New-TestFile 'Inbox/View-Sprint.md' (Text @('# Sprint', '', '```tasks', 'tag includes #group/alpha', '```'))
    New-TestFile 'Tasks/View-Open.md' (Text @('# Open', '', 'Filter: #group/alpha.'))
    New-TestFile 'Inbox/View-Other.md' (Text @('# Other', '', '```tasks', 'tag includes #group/beta-two', '```'))
    New-TestFile 'Archive/View-Old.md' (Text @('# Old', '', '#group/alpha'))
    New-TestFile 'Areas/G1/Archive/View-Older.md' (Text @('# Older', '', '#group/alpha'))
    New-TestFile 'Inbox/Notes.md' (Text @('#group/alpha in a non-view file'))
}
function Format-Group($G) { "$($G.Group):$($G.Open):$($G.Closed):$(@($G.Files) -join '+'):$(@($G.Views) -join '+')" }

Run-Test 'groups: counts, Files, sort order, object shape' {
    Set-GroupFixtures
    $r = Invoke-Tasks 'groups'
    Expect ($r.Code -eq 0) "exit $($r.Code): $($r.Err)"
    $got = @($r.Json | ForEach-Object { Format-Group $_ }) -join ' '
    $want = 'alpha:2:1:Areas/G1/Tasks.md+Projects/G2/Tasks.md: beta:1:0:Areas/G1/Tasks.md: beta-two:1:0:Projects/G2/Tasks.md:'
    Expect ($got -eq $want) "got  $got`n    want $want"
    $props = @(@($r.Json)[0].PSObject.Properties.Name) -join ','
    Expect ($props -eq 'Group,Open,Closed,Files,Views') $props
    $beta = @($r.Json)[1]
    Expect ($beta.Files -is [array] -and $beta.Views -is [array] -and $beta.Views.Count -eq 0) 'single Files and empty Views are arrays'
    Expect ($r.Out -match '"Views": \[\]') "raw empty Views: $($r.Out)"
    Ok
}

Run-Test 'groups: Views lists matching View-*.md repo-wide, Archive and other tags excluded' {
    Set-GroupFixtures
    Set-ViewFixtures
    $r = Invoke-Tasks 'groups'
    Expect ($r.Code -eq 0) "exit $($r.Code): $($r.Err)"
    $got = @($r.Json | ForEach-Object { Format-Group $_ }) -join ' '
    $want = 'alpha:2:1:Areas/G1/Tasks.md+Projects/G2/Tasks.md:Inbox/View-Sprint.md+Tasks/View-Open.md beta:1:0:Areas/G1/Tasks.md: beta-two:1:0:Projects/G2/Tasks.md:Inbox/View-Other.md'
    Expect ($got -eq $want) "got  $got`n    want $want"
    Ok
}

Run-Test 'groups: pwsh -File, -Path scopes counts but not Views' {
    Set-GroupFixtures
    Set-ViewFixtures
    $before = (Get-TestFileContent 'Areas/G1/Tasks.md') + (Get-TestFileContent 'Projects/G2/Tasks.md')
    $r = Invoke-TasksFile 'groups' @('-Path', 'Areas')
    Expect ($r.Code -eq 0) "exit $($r.Code): $($r.Err)"
    $got = @($r.Json | ForEach-Object { Format-Group $_ }) -join ' '
    $want = 'alpha:1:1:Areas/G1/Tasks.md:Inbox/View-Sprint.md+Tasks/View-Open.md beta:1:0:Areas/G1/Tasks.md:'
    Expect ($got -eq $want) "got  $got`n    want $want"
    $f = Invoke-TasksFile 'groups' @('-Path', 'Projects/G2/Tasks.md')
    $gotF = @($f.Json | ForEach-Object { Format-Group $_ }) -join ' '
    Expect ($gotF -eq 'alpha:1:0:Projects/G2/Tasks.md:Inbox/View-Sprint.md+Tasks/View-Open.md beta-two:1:0:Projects/G2/Tasks.md:Inbox/View-Other.md') "file scope: $gotF"
    Expect (((Get-TestFileContent 'Areas/G1/Tasks.md') + (Get-TestFileContent 'Projects/G2/Tasks.md')) -ceq $before) 'groups changed a file'
    Ok
}

Run-Test 'groups: no grouping tags returns [] exactly' {
    New-TestFile 'Inbox/View-Sprint.md' (Text @('#group/alpha'))
    $A2 = @('## 🔥 Current', '- [ ] grouped-looking #groups/x #mygroup/y | 🆔 1 ➕ 2026-01-01')
    New-TestFile 'Areas/N/Tasks.md' (Text $A2)
    $r = Invoke-TasksFile 'groups'
    Expect ($r.Code -eq 0 -and $r.Out.Trim() -eq '[]') "out: $($r.Out) $($r.Err)"
    Expect-Error (Invoke-Tasks 'groups' @{ Path = 'No/Such' }) '^Path not found: No/Such$'
    Ok
}

# ===========================================================================
Write-Host "`n-- add --"

Run-Test 'add: defaults (Backlog, todo, next ID, created today), blank-separated insertion' {
    Set-Fixtures
    $r = Invoke-Tasks 'add' @{ Path = $ARel; Title = 'New thing' }
    Expect ($r.Code -eq 0) "exit $($r.Code): $($r.Err)"
    $line = "- [ ] New thing | 🆔 12 ➕ $today"
    Expect-File $ARel (Text (Splice $A 20 0 @($line, '')))
    Expect ($r.Json.Id -eq '12' -and $r.Json.IdNumber -eq 12 -and $r.Json.Section -eq 'Backlog' -and $r.Json.Status -eq 'todo' -and $r.Json.LineNumber -eq 21 -and $r.Json.Created -eq $today -and $r.Json.Raw -eq $line) "out $($r.Out)"
    Ok
}

Run-Test 'add: every optional field, children plain and pre-bulleted' {
    Set-Fixtures
    $r = Invoke-Tasks 'add' @{ Path = $ARel; Title = 'Full'; Section = 'current'; Status = 'in-progress'; Text = 'with $285 text'
        Tags = @('#group/w', 'b'); Priority = 'high'; Start = '2026-03-01'; Scheduled = '2026-03-02'; Due = '2026-03-03'
        Children = @('plain child', '- [ ] box child', '- dash child') }
    Expect ($r.Code -eq 0) "exit $($r.Code): $($r.Err)"
    $line = "- [/] **Full** - with `$285 text #group/w #b | ⏫ 🛫 2026-03-01 ⏳ 2026-03-02 📅 2026-03-03 🆔 12 ➕ $today"
    Expect-File $ARel (Text (Splice $A 11 0 @($line, '    - plain child', '    - [ ] box child', '    - dash child', '')))
    $j = $r.Json
    Expect ($j.Priority -eq 'high' -and $j.Start -eq '2026-03-01' -and $j.Scheduled -eq '2026-03-02' -and $j.Due -eq '2026-03-03' -and (@($j.Tags) -join ',') -eq 'group/w,b' -and $j.Children.Count -eq 3 -and $j.Text -eq 'with $285 text') "out $($r.Out)"
    Ok
}

Run-Test 'add: compact section (heading then item) gets heading blank, no item blank' {
    Set-Fixtures
    $r = Invoke-Tasks 'add' @{ Path = 'Projects/P'; Title = 'Zero'; Section = 'Current' }
    Expect ($r.Code -eq 0) "exit $($r.Code): $($r.Err)"
    Expect-File $BRel (Text (Splice $B 3 0 @('', "- [ ] Zero | 🆔 12 ➕ $today")))
    Ok
}

Run-Test 'add: empty section before a heading, and at end of file' {
    Set-Fixtures
    $r1 = Invoke-Tasks 'add' @{ Path = $BRel; Title = 'Back' }
    Expect-File $BRel (Text (Splice $B 7 0 @("- [ ] Back | 🆔 12 ➕ $today", '')))
    New-TestFile 'E/Tasks.md' (Text @('## 🔥 Current', '', '## 📋 Backlog'))
    $r2 = Invoke-Tasks 'add' @{ Path = 'E/Tasks.md'; Title = 'At end' }
    Expect ($r1.Code -eq 0 -and $r2.Code -eq 0) "$($r1.Err) $($r2.Err)"
    Expect-File 'E/Tasks.md' (Text @('## 🔥 Current', '', '## 📋 Backlog', '', "- [ ] At end | 🆔 13 ➕ $today"))
    Ok
}

Run-Test 'add: empty section directly followed by the next heading' {
    New-TestFile 'T/Tasks.md' (Text @('## 🔥 Current', '## 📋 Backlog'))
    $r = Invoke-Tasks 'add' @{ Path = 'T'; Title = 'x'; Section = 'Current' }
    Expect ($r.Code -eq 0) $r.Err
    Expect-File 'T/Tasks.md' (Text @('## 🔥 Current', '', "- [ ] x | 🆔 1 ➕ $today", '', '## 📋 Backlog'))
    Ok
}

Run-Test 'add: CRLF file keeps CRLF and untouched bytes' {
    New-TestFile $ARel (Text $A "`r`n")
    $r = Invoke-Tasks 'add' @{ Path = $ARel; Title = 'Crlf' }
    Expect ($r.Code -eq 0) $r.Err
    Expect-File $ARel (Text (Splice $A 20 0 @("- [ ] Crlf | 🆔 5 ➕ $today", '')) "`r`n")
    Expect (Test-NoBom $ARel) 'BOM written'
    Ok
}

Run-Test 'add: reminders' {
    Set-Fixtures
    $r = Invoke-Tasks 'add' @{ Path = $ARel; Title = 'Remind two'; Section = 'Reminders' }
    Expect ($r.Code -eq 0) $r.Err
    Expect-File $ARel (Text (Splice $A 7 0 @('- Remind two')))
    $props = @($r.Json.PSObject.Properties.Name) -join ','
    Expect ($props -eq 'File,LineNumber,Text' -and $r.Json.LineNumber -eq 8 -and $r.Json.Text -eq 'Remind two' -and $r.Json.File -eq $ARel) $r.Out
    Expect-Error (Invoke-Tasks 'add' @{ Path = $ARel; Title = 'r'; Section = 'Reminders'; Tags = 'x' }) '^-Tags does not apply to a reminder; reminders take only -Title$'
    Ok
}

Run-Test 'add: errors (missing file, missing section, bad values)' {
    Set-Fixtures
    New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'Empty') | Out-Null
    $r = Invoke-Tasks 'add' @{ Path = 'Empty'; Title = 'x' }
    Expect-Error $r '^Tasks\.md not found: .*Empty.Tasks\.md$'
    Expect-Error (Invoke-Tasks 'add' @{ Path = $BRel; Title = 'x'; Section = 'Blocked' }) "^Section 'Blocked' not found in Projects/P/Tasks\.md$"
    Expect-Error (Invoke-Tasks 'add' @{ Path = $BRel }) '^-Action add requires -Title$'
    Expect-Error (Invoke-Tasks 'add' @{ Title = 'x' }) '^-Action add requires -Path$'
    Expect-Error (Invoke-Tasks 'add' @{ Path = $BRel; Title = 'x'; Due = '10/24/2026' }) "^Invalid -Due '10/24/2026'\. Use yyyy-MM-dd or none$"
    Expect-Error (Invoke-Tasks 'add' @{ Path = $BRel; Title = 'x'; Priority = 'urgent' }) "^Unknown priority 'urgent'\. Use one of: highest, high, medium, low, lowest, none$"
    Expect-Error (Invoke-Tasks 'add' @{ Path = $BRel; Title = 'x'; Status = 'done' }) '^Use -Action done or -Action cancel to finish a task; add takes -Status todo or in-progress$'
    Expect-Error (Invoke-Tasks 'add' @{ Path = $BRel; Title = 'x'; Tags = '12' }) "^Invalid tag '12'\."
    Expect-File $BRel (Text $B)
    Ok
}

# ===========================================================================
Write-Host "`n-- update --"

Run-Test 'update: every line field, none clears, tags add/remove' {
    Set-Fixtures
    $r = Invoke-Tasks 'update' @{ Id = 3; Title = 'Gamma two'; Text = 'more'; AddTag = @('new', 'HOME'); RemoveTag = '#home'
        Priority = 'low'; Start = '2026-04-01'; Scheduled = '2026-04-02'; Due = '2026-04-03' }
    Expect ($r.Code -eq 0) $r.Err
    $line = '- [ ] **Gamma two** - more #new | 🔽 🛫 2026-04-01 ⏳ 2026-04-02 📅 2026-04-03 🆔 3 ➕ 2026-01-03'
    Expect-File $ARel (Text (Splice $A 20 1 @($line)))
    Expect ($r.Json.Title -eq 'Gamma two' -and $r.Json.Priority -eq 'low' -and (@($r.Json.Tags) -join ',') -eq 'new') $r.Out
    $r2 = Invoke-Tasks 'update' @{ Id = 3; Priority = 'none'; Start = 'none'; Scheduled = 'none'; Due = 'none'; Text = '' }
    Expect ($r2.Code -eq 0) $r2.Err
    Expect-File $ARel (Text (Splice $A 20 1 @('- [ ] Gamma two #new | 🆔 3 ➕ 2026-01-03')))
    Ok
}

Run-Test 'update: status, add child' {
    Set-Fixtures
    $r = Invoke-Tasks 'update' @{ Id = 1; Status = 'in-progress'; AddChild = @('second child', '- [ ] box') }
    Expect ($r.Code -eq 0) $r.Err
    Expect-File $ARel (Text (Splice $A 11 2 @('- [/] **Alpha** - first | 🆔 1 ➕ 2026-01-01', '    - alpha child', '    - second child', '    - [ ] box')))
    Expect ($r.Json.Status -eq 'in-progress' -and $r.Json.Children.Count -eq 3) $r.Out
    Ok
}

Run-Test 'update: -Section moves the block with its children' {
    Set-Fixtures
    $r = Invoke-Tasks 'update' @{ Id = 1; Section = 'Backlog' }
    Expect ($r.Code -eq 0) $r.Err
    $exp = @(
        $A[0..9]
        ''
        '- [/] Beta #group/x | 📅 2026-02-01 🆔 2 ➕ 2026-01-02'
        ''
        '## 🧱 Blocked'
        ''
        '## 📋 Backlog'
        ''
        '- [ ] **Alpha** - first | 🆔 1 ➕ 2026-01-01'
        '    - alpha child'
        ''
        '- [ ] Gamma #home | ⏫ 🆔 3 ➕ 2026-01-03'
        $A[21..26]
    )
    Expect-File $ARel (Text $exp)
    Expect ($r.Json.Section -eq 'Backlog' -and $r.Json.LineNumber -eq 18 -and $r.Json.Children.Count -eq 1) $r.Out
    Ok
}

Run-Test 'update: compact file move keeps the compact style' {
    Set-Fixtures
    $r = Invoke-Tasks 'update' @{ Id = 11; Section = 'SideQuests' }
    Expect-Error $r "^Section 'SideQuests' not found in Projects/P/Tasks\.md$"
    $r = Invoke-Tasks 'update' @{ Id = 10; Section = 'Backlog' }
    Expect ($r.Code -eq 0) $r.Err
    Expect-File $BRel (Text @('# P Tasks', '', '## 🔥 Current', '- [ ] Two | 🆔 11 ➕ 2026-01-01', '## 📋 Backlog', '', '- [ ] One | 🆔 10 ➕ 2026-01-01', '', '## ✅ Done'))
    Ok
}

Run-Test 'update: errors (done/cancelled status, Done section, unknown ID, nothing to change)' {
    Set-Fixtures
    Expect-Error (Invoke-Tasks 'update' @{ Id = 1; Status = 'done' }) '^Use -Action done or -Action cancel to set status done$'
    Expect-Error (Invoke-Tasks 'update' @{ Id = 1; Status = 'cancelled' }) '^Use -Action done or -Action cancel to set status cancelled$'
    Expect-Error (Invoke-Tasks 'update' @{ Id = 1; Section = 'Done' }) '^Use -Action done or -Action cancel to move a task to Done$'
    Expect-Error (Invoke-Tasks 'update' @{ Id = 1; Section = 'Reminders' }) '^A task cannot move to Reminders$'
    Expect-Error (Invoke-Tasks 'update' @{ Id = 999; Title = 'x' }) '^Task 999 not found$'
    Expect-Error (Invoke-Tasks 'update' @{ Id = 1 }) '^-Action update needs at least one of: -Title, -Text, -AddTag, -RemoveTag, -Priority, -Start, -Scheduled, -Due, -Status, -Section, -AddChild$'
    Expect-Error (Invoke-Tasks 'update' @{ Title = 'x' }) '^-Action update requires -Id$'
    Expect-Error (Invoke-Tasks 'update' @{ Id = @(1, 2); Title = 'x' }) '^-Action update takes exactly one -Id$'
    Expect-Error (Invoke-Tasks 'update' @{ Id = 1; Start = '2026-13-01' }) "^Invalid -Start '2026-13-01'"
    Expect-File $ARel (Text $A)
    Ok
}

Run-Test 'update: duplicate ID is an error naming both places' {
    Set-Fixtures
    New-TestFile 'Areas/D/Tasks.md' (Text @('## 🔥 Current', '- [ ] dup | 🆔 1'))
    Expect-Error (Invoke-Tasks 'update' @{ Id = 1; Title = 'x' }) '^Task 1 is on more than one line \(Areas/A/Tasks\.md:12, Areas/D/Tasks\.md:2\); fix the duplicate ID first$'
    Ok
}

# ===========================================================================
Write-Host "`n-- done / cancel --"

Run-Test 'done: moves block to top of Done, drops fields/tags/text, keeps children' {
    Set-Fixtures
    $r = Invoke-Tasks 'update' @{ Id = 1; AddTag = 't'; Due = '2026-05-01'; Priority = 'high' }
    $r = Invoke-Tasks 'done' @{ Id = 1 }
    Expect ($r.Code -eq 0) $r.Err
    $exp = @(
        $A[0..9]
        ''
        '- [/] Beta #group/x | 📅 2026-02-01 🆔 2 ➕ 2026-01-02'
        $A[15..25]
        "- [x] Alpha | 🆔 1 ➕ 2026-01-01 ✅ $today"
        '    - alpha child'
        ''
        $A[26]
    )
    Expect-File $ARel (Text $exp)
    $j = $r.Json
    Expect ($j.Status -eq 'done' -and $j.DoneDate -eq $today -and $j.Section -eq 'Done' -and $j.Title -eq 'Alpha' -and $j.Text -eq '' -and $j.Tags.Count -eq 0 -and $null -eq $j.Priority -and $null -eq $j.Due -and $j.Created -eq '2026-01-01' -and $j.Children.Count -eq 1) $r.Out
    Expect ($j.PSObject.Properties.Name -contains 'LinkedDoc' -and $null -eq $j.LinkedDoc) 'LinkedDoc null'
    Ok
}

Run-Test 'done: keeps wikilinks from the text and drops the rest of it' {
    Set-Fixtures
    $r = Invoke-Tasks 'update' @{ Id = 1; Text = 'context for alpha - See [[Plan-X]] and [[Other-Doc|alias]]' }
    Expect ($r.Code -eq 0) $r.Err
    $r = Invoke-Tasks 'done' @{ Id = 1 }
    Expect ($r.Code -eq 0) $r.Err
    Expect ($r.Json.Text -eq '[[Plan-X]] [[Other-Doc|alias]]') $r.Out
    Expect ($r.Json.Raw -eq "- [x] **Alpha** - [[Plan-X]] [[Other-Doc|alias]] | 🆔 1 ➕ 2026-01-01 ✅ $today") $r.Json.Raw
    Ok
}

Run-Test 'cancel: symbol and cancelled date; compact Done at end of file' {
    Set-Fixtures
    $r = Invoke-Tasks 'cancel' @{ Id = 11 }
    Expect ($r.Code -eq 0) $r.Err
    Expect-File $BRel (Text @('# P Tasks', '', '## 🔥 Current', '- [ ] One | 🆔 10 ➕ 2026-01-01', '## 📋 Backlog', '', '## ✅ Done', '', "- [-] Two | 🆔 11 ➕ 2026-01-01 ❌ $today"))
    Expect ($r.Json.Status -eq 'cancelled' -and $r.Json.CancelledDate -eq $today -and $null -eq $r.Json.DoneDate) $r.Out
    Expect-Error (Invoke-Tasks 'done' @{ Id = 11 }) '^Task 11 is already cancelled$'
    Expect-Error (Invoke-Tasks 'cancel' @{ Id = 4 }) '^Task 4 is already done$'
    Ok
}

Run-Test 'done: LinkedDoc for a Task- link (present, missing) and null for a plan link' {
    New-TestFile 'Areas/L/Tasks.md' (Text @(
        '## 🔥 Current'
        ''
        '- [ ] [[Task-20-Has-Doc]] #t | 📅 2026-05-01 🆔 20 ➕ 2026-01-01'
        '- [ ] [[Task-21-No-Doc]] | 🆔 21 ➕ 2026-01-01'
        '- [ ] [[Plan-Thing]] - do X | 🆔 22 ➕ 2026-01-01'
        ''
        '## ✅ Done'
    ))
    New-TestFile 'Areas/L/Inbox/Task-20-Has-Doc.md' "# Has Doc`n"
    New-TestFile 'Areas/L/Plan-Thing.md' "# Plan`n"
    $a = Invoke-Tasks 'done' @{ Id = 20 }
    $b = Invoke-Tasks 'done' @{ Id = 21 }
    $c = Invoke-Tasks 'done' @{ Id = 22 }
    Expect ($a.Json.LinkedDoc -eq (Join-Path $testRoot 'Areas' 'L' 'Inbox' 'Task-20-Has-Doc.md')) "a: $($a.Json.LinkedDoc) $($a.Err)"
    Expect ($a.Json.Title -eq '[[Task-20-Has-Doc]]' -and $a.Json.Promoted) 'title kept as link'
    Expect ($b.Code -eq 0 -and $null -eq $b.Json.LinkedDoc) "b: $($b.Out)"
    Expect ($c.Code -eq 0 -and $null -eq $c.Json.LinkedDoc -and $c.Json.Title -eq '[[Plan-Thing]]') "c: $($c.Out)"
    Expect-File 'Areas/L/Tasks.md' (Text @(
        '## 🔥 Current'
        ''
        '## ✅ Done'
        ''
        "- [x] [[Plan-Thing]] | 🆔 22 ➕ 2026-01-01 ✅ $today"
        "- [x] [[Task-21-No-Doc]] | 🆔 21 ➕ 2026-01-01 ✅ $today"
        "- [x] [[Task-20-Has-Doc]] | 🆔 20 ➕ 2026-01-01 ✅ $today"
    ))
    Ok
}

# ===========================================================================
Write-Host "`n-- promote --"

Run-Test 'promote: doc in Inbox/, template filled with Notes and dedent, line rewritten' {
    Set-Fixtures
    New-TestFile $ARel (Text (Splice $A 11 2 @('- [ ] **Alpha** - first part #t | 📅 2026-05-01 🆔 1 ➕ 2026-01-01', '      - six', '        - eight', '', '      - six again')))
    $r = Invoke-Tasks 'promote' @{ Id = 1 }
    Expect ($r.Code -eq 0) $r.Err
    $docRel = 'Areas/A/Inbox/Task-1-Alpha.md'
    Expect-File $docRel (Text @(
        '---'
        "doc.created: $today"
        'doc.type: Task'
        'agent.instructions:'
        '  - use_skill: "vault-tasks"'
        '    when: "editing this file"'
        '---'
        '# Alpha'
        ''
        'First part. Tracked in [[A/Tasks]].'
        ''
        '## Notes'
        ''
        '- six'
        '  - eight'
        ''
        '- six again'
    ))
    Expect-File $ARel (Text (Splice $A 11 2 @('- [ ] [[Task-1-Alpha]] #t | 📅 2026-05-01 🆔 1 ➕ 2026-01-01')))
    Expect ($r.Json.DocPath -eq (Join-Path $testRoot 'Areas' 'A' 'Inbox' 'Task-1-Alpha.md') -and $r.Json.Promoted -and $r.Json.Link -eq 'Task-1-Alpha' -and $r.Json.Children.Count -eq 0 -and $r.Json.Text -eq '') $r.Out
    Expect (Test-NoBom $docRel) 'BOM'
    Ok
}

Run-Test 'promote: beside Tasks.md without Inbox/, intro from title, no Notes, overrides' {
    Set-Fixtures
    $r = Invoke-Tasks 'promote' @{ Id = 10 }
    Expect ($r.Code -eq 0) $r.Err
    Expect-File 'Projects/P/Task-10-One.md' (Text @('---', "doc.created: $today", 'doc.type: Task', 'agent.instructions:', '  - use_skill: "vault-tasks"', '    when: "editing this file"', '---', '# One', '', 'One. Tracked in [[P/Tasks]].'))
    Expect-File $BRel (Text (Splice $B 3 1 @('- [ ] [[Task-10-One]] | 🆔 10 ➕ 2026-01-01')))
    $s = Invoke-Tasks 'promote' @{ Id = 11; Title = 'Second Thing'; Intro = 'Why it matters!' }
    Expect ($s.Code -eq 0) $s.Err
    Expect-File 'Projects/P/Task-11-Second-Thing.md' (Text @('---', "doc.created: $today", 'doc.type: Task', 'agent.instructions:', '  - use_skill: "vault-tasks"', '    when: "editing this file"', '---', '# Second Thing', '', 'Why it matters! Tracked in [[P/Tasks]].'))
    Ok
}

Run-Test 'promote: H1 in Title Case (rest of each word as typed), intro capitalized' {
    New-TestFile 'Tasks.md' (Text @('## 🔥 Current', '', '- [ ] **fix the `use_skill` MCP thing (now)** - because iPhone sync broke | 🆔 7 ➕ 2026-01-01'))
    $r = Invoke-Tasks 'promote' @{ Id = 7 }
    Expect ($r.Code -eq 0) $r.Err
    $doc = Get-TestFileContent 'Task-7-Fix-The-Use-Skill-MCP-Thing-Now.md'
    Expect ($doc.Contains("`n# Fix The ``use_skill`` MCP Thing (Now)`n")) "doc: $doc"
    Expect ($doc.Contains("`nBecause iPhone sync broke. Tracked in [[Tasks]].`n")) "doc: $doc"
    $s = Invoke-Tasks 'add' @{ Path = 'Tasks.md'; Title = 'x'; Section = 'Current' }
    $t = Invoke-Tasks 'promote' @{ Id = 8; Title = 'an override title'; Intro = 'lower intro' }
    $doc2 = Get-TestFileContent 'Task-8-An-Override-Title.md'
    Expect ($doc2.Contains("`n# An Override Title`n") -and $doc2.Contains("`nLower intro. Tracked in [[Tasks]].`n")) "doc2: $doc2 $($t.Err)"
    Ok
}

Run-Test 'write verbs stamp a missing created date on the line they touch' {
    New-TestFile 'Tasks.md' (Text @('## 🔥 Current', '', '- [ ] a | 🆔 1', '- [ ] b | 🆔 2', '- [ ] c | 🆔 3', '', '## ✅ Done'))
    $u = Invoke-Tasks 'update' @{ Id = 1; Title = 'a2' }
    Expect ($u.Code -eq 0 -and $u.Json.Created -eq $today) "update: $($u.Out) $($u.Err)"
    $d = Invoke-Tasks 'done' @{ Id = 2 }
    $c = Invoke-Tasks 'cancel' @{ Id = 3 }
    Expect ($d.Json.Created -eq $today -and $c.Json.Created -eq $today) 'done/cancel stamp created'
    Expect-File 'Tasks.md' (Text @('## 🔥 Current', '', "- [ ] a2 | 🆔 1 ➕ $today", '', '## ✅ Done', '', "- [-] c | 🆔 3 ➕ $today ❌ $today", "- [x] b | 🆔 2 ➕ $today ✅ $today"))
    New-TestFile 'Tasks.md' (Text @('## 🔥 Current', '', '- [ ] p | 🆔 4'))
    $p = Invoke-Tasks 'promote' @{ Id = 4 }
    Expect ($p.Code -eq 0) $p.Err
    Expect-File 'Tasks.md' (Text @('## 🔥 Current', '', "- [ ] [[Task-4-P]] | 🆔 4 ➕ $today"))
    Ok
}

Run-Test 'pwsh -File: comma- and newline-delimited array parameters' {
    Set-Fixtures
    $nl = "`n"
    $r = Invoke-TasksFile 'add' @('-Path', $ARel, '-Title', 'Filed', '-Tags', 'a, b,,#c', '-Children', "one, with comma${nl}- [ ] two")
    Expect ($r.Code -eq 0) "add: $($r.Err)"
    Expect ((@($r.Json.Tags) -join ',') -eq 'a,b,c' -and $r.Json.Children.Count -eq 2 -and $r.Json.Children[0] -eq '    - one, with comma' -and $r.Json.Children[1] -eq '    - [ ] two') $r.Out
    $l = Invoke-TasksFile 'list' @('-Id', '12, 3', '-Section', 'Backlog,Current', '-Status', 'todo,in-progress', '-Tag', 'nope,c')
    Expect ((@($l.Json | ForEach-Object Id) -join ',') -eq '12') "list: $($l.Out) $($l.Err)"
    $u = Invoke-TasksFile 'update' @('-Id', '12', '-AddTag', 'x,y', '-RemoveTag', 'a,b', '-AddChild', "three, too`r`nfour")
    Expect ($u.Code -eq 0 -and (@($u.Json.Tags) -join ',') -eq 'c,x,y' -and $u.Json.Children.Count -eq 4 -and $u.Json.Children[3] -eq '    - four') "update: $($u.Out) $($u.Err)"
    Expect-Error (Invoke-TasksFile 'update' @('-Id', '1,2', '-Title', 'x')) '^-Action update takes exactly one -Id$'
    Expect-Error (Invoke-TasksFile 'list' @('-Id', 'abc')) "^Invalid -Id 'abc'\. IDs are integers$"
    Ok
}

Run-Test 'promote: errors when already promoted or the doc exists' {
    Set-Fixtures
    New-TestFile 'Areas/A/Inbox/Task-3-Gamma.md' "# Existing`n"
    Expect-Error (Invoke-Tasks 'promote' @{ Id = 3 }) '^Task doc already exists: .*Task-3-Gamma\.md$'
    Expect-File $ARel (Text $A)
    $ok = Invoke-Tasks 'promote' @{ Id = 1 }
    Expect-Error (Invoke-Tasks 'promote' @{ Id = 1 }) '^Task 1 is already promoted: its title is the link \[\[Task-1-Alpha\]\]$'
    Ok
}

# ===========================================================================
Write-Host "`n-- prune --"

$P = @(
    '## 🔥 Current'
    ''
    '- [ ] Open | 🆔 1'
    ''
    '## ✅ Done'
    ''
    "- [x] Recent | 🆔 2 ✅ $(DaysAgo 2)"
    ''
    "- [x] Old | 🆔 3 ✅ $(DaysAgo 10)"
    '    - old child'
    ''
    "- [-] Old cancel | 🆔 4 ❌ $(DaysAgo 8)"
    "- [x] Boundary | 🆔 5 ✅ $(DaysAgo 7)"
    '- [x] Undated | 🆔 6'
)

Run-Test 'prune: preview selects by cutoff and changes nothing' {
    New-TestFile 'Tasks.md' (Text $P)
    $r = Invoke-Tasks 'prune'
    Expect ($r.Code -eq 0) $r.Err
    Expect ($r.Json.Applied -eq $false -and (@($r.Json.Tasks | ForEach-Object Id) -join ',') -eq '3,4') $r.Out
    Expect ($r.Json.Tasks -is [array]) 'Tasks array'
    Expect-File 'Tasks.md' (Text $P)
    Ok
}

Run-Test 'prune: -Days override and -Apply removes blocks without double blanks' {
    New-TestFile 'Tasks.md' (Text $P)
    $r = Invoke-Tasks 'prune' @{ Days = 1; Apply = $true }
    Expect ($r.Code -eq 0) $r.Err
    Expect ($r.Json.Applied -eq $true -and (@($r.Json.Tasks | ForEach-Object Id) -join ',') -eq '2,3,4,5') $r.Out
    Expect-File 'Tasks.md' (Text @('## 🔥 Current', '', '- [ ] Open | 🆔 1', '', '## ✅ Done', '', '- [x] Undated | 🆔 6'))
    $e = Invoke-Tasks 'prune' @{ Days = 1 }
    Expect ($e.Out -match '"Tasks": \[\]') "empty Tasks: $($e.Out)"
    Ok
}

Run-Test 'prune: removing everything leaves the Done heading last' {
    New-TestFile 'Tasks.md' (Text @('## 🔥 Current', '', '## ✅ Done', '', "- [x] a | ✅ $(DaysAgo 30)", '', "- [x] b | ✅ $(DaysAgo 30)"))
    $r = Invoke-Tasks 'prune' @{ Apply = $true }
    Expect ($r.Code -eq 0) $r.Err
    Expect-File 'Tasks.md' (Text @('## 🔥 Current', '', '## ✅ Done'))
    Ok
}

# ===========================================================================
Write-Host "`n-- backfill --"

Run-Test 'backfill: stamps across two files in order, unique IDs, idempotent' {
    New-TestFile 'A/Tasks.md' (Text @(
        '## 🔔 Reminders'
        '- reminder stays'
        '## 🔥 Current'
        '- [ ] first'
        '    - [ ] nested child | 🆔 77'
        '- [ ] has id | 🆔 40'
        '- [ ] word id | 🆔 abc'
        '## ✅ Done'
        '- [x] done no id | ✅ 2026-01-01'
    ))
    New-TestFile 'B/Tasks.md' (Text @('## 📋 Backlog', '- [ ] **b one** - text #t | 📅 2026-02-02', '## Notes', '- [ ] not a task'))
    $r = Invoke-Tasks 'backfill'
    Expect ($r.Code -eq 0) $r.Err
    $got = @($r.Json | ForEach-Object { "$($_.File):$($_.LineNumber):$($_.Id):$($_.StampedId):$($_.StampedCreated)" }) -join ' '
    $want = 'A/Tasks.md:4:41:True:True A/Tasks.md:6:40:False:True A/Tasks.md:9:42:True:True B/Tasks.md:2:43:True:True'
    Expect ($got -eq $want) "got  $got`n    want $want"
    Expect-File 'A/Tasks.md' (Text @(
        '## 🔔 Reminders'
        '- reminder stays'
        '## 🔥 Current'
        "- [ ] first | 🆔 41 ➕ $today"
        '    - [ ] nested child | 🆔 77'
        "- [ ] has id | 🆔 40 ➕ $today"
        '- [ ] word id | 🆔 abc'
        '## ✅ Done'
        "- [x] done no id | 🆔 42 ➕ $today ✅ 2026-01-01"
    ))
    Expect-File 'B/Tasks.md' (Text @('## 📋 Backlog', "- [ ] **b one** - text #t | 📅 2026-02-02 🆔 43 ➕ $today", '## Notes', '- [ ] not a task'))
    $before = (Get-TestFileContent 'A/Tasks.md') + (Get-TestFileContent 'B/Tasks.md')
    $again = Invoke-Tasks 'backfill'
    Expect ($again.Code -eq 0 -and $again.Out.Trim() -eq '[]') "second run: $($again.Out)"
    Expect (((Get-TestFileContent 'A/Tasks.md') + (Get-TestFileContent 'B/Tasks.md')) -ceq $before) 'second run changed files'
    Ok
}

Run-Test 'backfill: -Path scope still takes the next ID from the whole repo' {
    New-TestFile 'A/Tasks.md' (Text @('## 🔥 Current', '- [ ] a'))
    New-TestFile 'B/Tasks.md' (Text @('## 🔥 Current', '- [ ] b | 🆔 9 ➕ 2026-01-01'))
    $r = Invoke-Tasks 'backfill' @{ Path = 'A' }
    Expect ($r.Code -eq 0 -and @($r.Json).Count -eq 1 -and @($r.Json)[0].Id -eq '10') $r.Out
    Expect-File 'A/Tasks.md' (Text @('## 🔥 Current', "- [ ] a | 🆔 10 ➕ $today"))
    Ok
}

# ===========================================================================
Write-Host "`n-- real files --"

Run-Test 'smoke: list and check over copies of every real Tasks.md' {
    $n = 0
    foreach ($f in Get-ChildItem -Path (Join-Path $vaultRoot 'Areas'), (Join-Path $vaultRoot 'Projects') -Filter 'Tasks.md' -Recurse -Depth 1 -File) {
        $rel = $f.FullName.Substring($vaultRoot.Length)
        New-TestFile $rel ([System.IO.File]::ReadAllText($f.FullName))
        $n++
    }
    $l = Invoke-Tasks 'list'
    $c = Invoke-Tasks 'check'
    $b = Invoke-Tasks 'backfill'
    $l2 = Invoke-Tasks 'list'
    $c2 = Invoke-Tasks 'check'
    Expect ($n -ge 9) "copied $n files"
    Expect ($l.Code -eq 0 -and @($l.Json).Count -gt 0) "list: $($l.Err)"
    Expect ($c.Code -eq 0) "check: $($c.Err)"
    Expect ($b.Code -eq 0) "backfill: $($b.Err)"
    Expect (@($l2.Json).Count -eq @($l.Json).Count) 'backfill changed the task count'
    $left = @($c2.Json | Where-Object { $_.Code -in 'MissingId', 'MissingCreated', 'DuplicateId' })
    Expect ($left.Count -eq 0) "after backfill: $(@($left | ForEach-Object { "$($_.File):$($_.LineNumber):$($_.Code)" }) -join ', ')"
    Ok
}

} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
