# vault-tasks.unit-tests.ps1
# Direct unit tests for _shared/vault-tasks.ps1 (see Skill-Dev.md's Testing Shared Scripts
# section). Line parse/emit cases are in-memory and use Assert-That; the fixtures are real
# lines from the vault's Tasks.md files. File-model, discovery, ID, and writer cases run in
# a throwaway git worktree via Initialize-TestWorktree / Run-Test.
# Usage: pwsh -NoProfile -File .claude/skills/_shared/tests/vault-tasks.unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' 'vault-tasks.ps1')
. (Join-Path $PSScriptRoot '..' 'vault-test-common.ps1')

$sep = [System.IO.Path]::DirectorySeparatorChar
$modeled = 'Symbol', 'Status', 'Id', 'IdNumber', 'Title', 'Text', 'Tags', 'Link', 'Promoted', 'Priority',
           'Start', 'Scheduled', 'Due', 'Created', 'DoneDate', 'CancelledDate', 'Extra'

# Compare two task objects on every modeled field; returns '' when equal, else the diffs.
function Compare-Task($Left, $Right) {
    $diffs = foreach ($p in $modeled) {
        $a = $Left.$p; $b = $Right.$p
        if ($a -is [array] -or $b -is [array]) { $a = (@($a) -join '|'); $b = (@($b) -join '|') }
        if ("$a" -ne "$b" -or ($null -eq $a) -ne ($null -eq $b)) { "$p '$a' vs '$b'" }
    }
    return ($diffs -join '; ')
}

# Assert the parse matches $Expect (hashtable of field -> value; arrays joined with '|').
function Assert-Parse([string]$Name, [string]$Line, [hashtable]$Expect) {
    $t = ConvertFrom-TaskLine -Line $Line
    if ($null -eq $t) { Assert-That $Name $false 'parse returned $null'; return }
    $bad = foreach ($k in $Expect.Keys) {
        $got = $t.$k; $want = $Expect[$k]
        if ($want -is [array]) { $want = $want -join '|'; $got = @($got) -join '|' }
        if ($null -eq $want) { if ($null -ne $got) { "$k='$got' (want null)" } }
        elseif ("$got" -cne "$want") { "$k='$got' (want '$want')" }
    }
    Assert-That $Name (-not $bad) ($bad -join '; ')
}

# Assert parse -> emit -> parse preserves every modeled field.
function Assert-RoundTrip([string]$Name, [string]$Line) {
    $t1 = ConvertFrom-TaskLine -Line $Line
    $emitted = ConvertTo-TaskLine -Task $t1
    $t2 = ConvertFrom-TaskLine -Line $emitted
    Assert-That $Name (-not (Compare-Task $t1 $t2)) "emitted: $emitted :: $(Compare-Task $t1 $t2)"
}

# ---- ConvertFrom-TaskLine: real-world lines --------------------------------
Write-Host "`nConvertFrom-TaskLine - real lines"

$all = @{ Id = $null; IdNumber = $null; Link = $null; Promoted = $false; Priority = $null; Start = $null; Scheduled = $null;
          Due = $null; Created = $null; DoneDate = $null; CancelledDate = $null; Tags = @(); Extra = @() }
function E([hashtable]$h) { $r = $all.Clone(); foreach ($k in $h.Keys) { $r[$k] = $h[$k] }; return $r }

Assert-Parse 'no fields, no pipe' '- [ ] Sign up for additional SPOT coverage' (E @{
    Symbol = ' '; Status = 'todo'; Title = 'Sign up for additional SPOT coverage'; Text = '' })

Assert-Parse 'bold title, pipe, priority only' '- [ ] **Unify vault templates with Obsidian template format** | 🔼' (E @{
    Title = 'Unify vault templates with Obsidian template format'; Text = ''; Priority = 'medium' })

Assert-Parse 'in-progress with text and created' '- [/] **Skill progressive disclosure audit** - See [[Plan-Skill-Progressive-Disclosure]]. | ➕ 2026-07-12' (E @{
    Status = 'in-progress'; Title = 'Skill progressive disclosure audit'; Text = 'See [[Plan-Skill-Progressive-Disclosure]].'; Created = '2026-07-12' })

Assert-Parse 'due + created, & and links in text' '- [ ] **Apply to INL 2174** - Software Developer & AI Automation Specialist; update a cover letter from the originals. See [[INL-2174-Software-Developer-AI-Automation-Specialist]] and [[Plan-INL-Applications]] | 📅 2026-10-24 ➕ 2026-10-12' (E @{
    Title = 'Apply to INL 2174'; Due = '2026-10-24'; Created = '2026-10-12'
    Text = 'Software Developer & AI Automation Specialist; update a cover letter from the originals. See [[INL-2174-Software-Developer-AI-Automation-Specialist]] and [[Plan-INL-Applications]]' })

Assert-Parse 'done with created and done date' '- [x] **Decide how DNS-over-HTTPS clients should be handled** | ➕ 2026-08-16 ✅ 2026-08-17' (E @{
    Status = 'done'; Title = 'Decide how DNS-over-HTTPS clients should be handled'; Created = '2026-08-16'; DoneDate = '2026-08-17' })

Assert-Parse 'cancelled, code span in title' '- [-] **Set `webserver.acl` on pihole** | ➕ 2026-08-16 ❌ 2026-08-16' (E @{
    Status = 'cancelled'; Title = 'Set `webserver.acl` on pihole'; Created = '2026-08-16'; CancelledDate = '2026-08-16' })

Assert-Parse 'strikethrough preserved in text' '- [/] **Build the vault-mcp skill** - ~~client-side start/troubleshoot + recovery~~ (completed) + elevation-driver; see [[Idea-Vault-MCP-Skill]]. Blocked until ... | ➕ 2026-07-19' (E @{
    Title = 'Build the vault-mcp skill'; Created = '2026-07-19'
    Text = '~~client-side start/troubleshoot + recovery~~ (completed) + elevation-driver; see [[Idea-Vault-MCP-Skill]]. Blocked until ...' })

Assert-Parse 'promoted link title with tag and id' '- [ ] [[Task-17-Reconsider-Task-System]] #group/weekend-2026-10-17 | 📅 2026-10-24 🆔 17 ➕ 2026-10-17' (E @{
    Title = '[[Task-17-Reconsider-Task-System]]'; Text = ''; Link = 'Task-17-Reconsider-Task-System'; Promoted = $true
    Tags = @('group/weekend-2026-10-17'); Due = '2026-10-24'; Id = '17'; IdNumber = 17; Created = '2026-10-17' })

Assert-Parse 'plain title with hyphen, tag, id' '- [ ] Mow, mulch leaves, string trim - evening, ~2h #group/weekend-2026-10-17 | 🆔 18 ➕ 2026-10-17' (E @{
    Title = 'Mow, mulch leaves, string trim - evening, ~2h'; Text = ''; Tags = @('group/weekend-2026-10-17'); Id = '18'; IdNumber = 18; Created = '2026-10-17' })

Assert-Parse 'aliased wikilink title: Link drops alias and path' '- [ ] [[Areas/Vault-Dev/Task-3-Foo|Foo]] | 🆔 3' (E @{
    Title = '[[Areas/Vault-Dev/Task-3-Foo|Foo]]'; Link = 'Task-3-Foo'; Promoted = $true; Id = '3'; IdNumber = 3 })

Assert-Parse 'link title with text' '- [ ] [[Task-4-Bar]] - waiting on parts | 🆔 4' (E @{
    Title = '[[Task-4-Bar]]'; Text = 'waiting on parts'; Link = 'Task-4-Bar'; Promoted = $true; Id = '4'; IdNumber = 4 })

Assert-Parse 'link inside plain title is not promoted' '- [ ] Request records; add history to [[Medical]]' (E @{
    Title = 'Request records; add history to [[Medical]]'; Promoted = $false; Link = $null })

Assert-Parse 'non-numeric id' '- [ ] Thing | 🆔 abc-1' (E @{ Id = 'abc-1'; IdNumber = $null })
Assert-Parse 'other status symbol kept raw' '- [?] Thing' (E @{ Symbol = '?'; Status = 'other' })
Assert-Parse 'upper X is done' '- [X] Thing' (E @{ Status = 'done' })
Assert-Parse 'numeric hash is not a tag' '- [ ] **custom header support (issue #10)**' (E @{ Title = 'custom header support (issue #10)'; Tags = @() })
Assert-Parse 'pipe with no fields' '- [ ] **Thing** |' (E @{ Title = 'Thing'; Text = '' })
Assert-Parse 'legacy middle pipes stay in text' '- [ ] **Task title** - context | for-whom | 📅 2026-06-30 ➕ 2026-06-19' (E @{
    Title = 'Task title'; Text = 'context | for-whom'; Due = '2026-06-30'; Created = '2026-06-19' })
Assert-Parse 'fields with no pipe' '- [ ] Thing 📅 2026-06-30 ⏫' (E @{ Title = 'Thing'; Due = '2026-06-30'; Priority = 'high' })
Assert-Parse 'all priorities: highest' '- [ ] a | 🔺' (E @{ Priority = 'highest' })
Assert-Parse 'all priorities: low'     '- [ ] a | 🔽' (E @{ Priority = 'low' })
Assert-Parse 'all priorities: lowest'  '- [ ] a | ⏬' (E @{ Priority = 'lowest' })
Assert-Parse 'start and scheduled' '- [ ] a | 🛫 2026-01-01 ⏳ 2026-01-02' (E @{ Start = '2026-01-01'; Scheduled = '2026-01-02' })
Assert-Parse 'tag after the fields is still a tag' '- [ ] a | 📅 2026-01-01 #later' (E @{ Title = 'a'; Due = '2026-01-01'; Tags = @('later') })

$scrambled = ConvertFrom-TaskLine '- [ ] Thing | ➕ 2026-01-01 🆔 5 📅 2026-02-02'
$canonical = ConvertFrom-TaskLine '- [ ] Thing | 📅 2026-02-02 🆔 5 ➕ 2026-01-01'
Assert-That 'scrambled field order parses the same as canonical' (-not (Compare-Task $scrambled $canonical)) (Compare-Task $scrambled $canonical)

Assert-Parse 'recurrence and depends-on go to Extra in order' '- [ ] Water plants | 📅 2026-02-02 🔁 every week ⛔ 3,4' (E @{
    Title = 'Water plants'; Due = '2026-02-02'; Extra = @('🔁 every week', '⛔ 3,4') })
Assert-RoundTrip 'recurrence and depends-on round-trip' '- [ ] Water plants | 📅 2026-02-02 🔁 every week ⛔ 3,4'
Assert-RoundTrip 'recurrence before a date field round-trips' '- [ ] Water plants 🔁 every day when done 📅 2026-02-02 🏁 delete'

Assert-Parse 'markdown link with # in target is not a tag' '- [ ] Call shop: [(208) 522-3050](tel:\(208\)%20522-3050) and read [doc](https://x.y/page#frag)' (E @{
    Tags = @(); Title = 'Call shop: [(208) 522-3050](tel:\(208\)%20522-3050) and read [doc](https://x.y/page#frag)' })
Assert-Parse 'wikilink heading and code span are not tags' '- [ ] See [[Plan#Posting Watch]] and `#notatag` #real' (E @{
    Tags = @('real'); Title = 'See [[Plan#Posting Watch]] and `#notatag`' })

Assert-Parse 'empty checkbox yields empty title' '- [ ]' (E @{ Title = ''; Text = '' })
Assert-Parse 'empty checkbox with trailing space' '- [ ] ' (E @{ Title = '' })

Assert-That 'indented checkbox is not a task line' ($null -eq (ConvertFrom-TaskLine '    - [ ] Research'))
Assert-That 'plain bullet is not a task line'       ($null -eq (ConvertFrom-TaskLine '- Halo releases 2026-07-28'))
Assert-That 'heading is not a task line'            ($null -eq (ConvertFrom-TaskLine '## Done'))
Assert-That 'Raw keeps the original line' ((ConvertFrom-TaskLine '- [ ] a | 🆔 1').Raw -eq '- [ ] a | 🆔 1')

# ---- ConvertTo-TaskLine ----------------------------------------------------
Write-Host "`nConvertTo-TaskLine"

$canonicalLines = @(
    '- [ ] Sign up for additional SPOT coverage'
    '- [/] **Skill progressive disclosure audit** - See [[Plan-Skill-Progressive-Disclosure]]. | ➕ 2026-07-12'
    '- [ ] **Apply to INL 2174** - Software Developer & AI Automation Specialist; update a cover letter from the originals. See [[INL-2174-Software-Developer-AI-Automation-Specialist]] and [[Plan-INL-Applications]] | 📅 2026-10-24 ➕ 2026-10-12'
    '- [/] **Build the vault-mcp skill** - ~~client-side start/troubleshoot + recovery~~ (completed) + elevation-driver; see [[Idea-Vault-MCP-Skill]]. Blocked until ... | ➕ 2026-07-19'
    '- [ ] [[Task-17-Reconsider-Task-System]] #group/weekend-2026-10-17 | 📅 2026-10-24 🆔 17 ➕ 2026-10-17'
    '- [ ] Mow, mulch leaves, string trim - evening, ~2h #group/weekend-2026-10-17 | 🆔 18 ➕ 2026-10-17'
    '- [x] Decide how DNS-over-HTTPS clients should be handled | ➕ 2026-08-16 ✅ 2026-08-17'
    '- [-] Set `webserver.acl` on pihole | ➕ 2026-08-16 ❌ 2026-08-16'
    '- [ ] **Full** - every field #a #b/c | 🔺 🛫 2026-01-01 ⏳ 2026-01-02 📅 2026-01-03 🆔 9 ➕ 2025-12-31 🔁 every week ⛔ 3,4'
    '- [ ] [[Task-4-Bar]] - waiting on parts | 🆔 4'
)
foreach ($l in $canonicalLines) {
    $e = ConvertTo-TaskLine (ConvertFrom-TaskLine $l)
    Assert-That "canonical line is byte-identical: $($l.Substring(0, [Math]::Min(40, $l.Length)))" ($e -ceq $l) "got: $e"
    Assert-RoundTrip "round trip: $($l.Substring(0, [Math]::Min(40, $l.Length)))" $l
}

Assert-That 'bold title with no text emits plain' ((ConvertTo-TaskLine (ConvertFrom-TaskLine '- [ ] **Unify vault templates** | 🔼')) -ceq '- [ ] Unify vault templates | 🔼')
Assert-That 'scrambled fields emit in canonical order' ((ConvertTo-TaskLine $scrambled) -ceq '- [ ] Thing | 📅 2026-02-02 🆔 5 ➕ 2026-01-01')
Assert-That 'no fields writes no pipe' ((ConvertTo-TaskLine @{ Title = 'x' }) -ceq '- [ ] x')
Assert-That 'hashtable input with Status only' ((ConvertTo-TaskLine @{ Status = 'in-progress'; Title = 'x'; Text = 'y'; Id = 7 }) -ceq '- [/] **x** - y | 🆔 7')
Assert-That 'tags given with # are not doubled' ((ConvertTo-TaskLine @{ Title = 'x'; Tags = @('#t') }) -ceq '- [ ] x #t')
Assert-That 'empty title with a field' ((ConvertTo-TaskLine @{ Title = ''; Due = '2026-01-01' }) -ceq '- [ ] | 📅 2026-01-01')
$threw = $false; try { ConvertTo-TaskLine @{ Title = 'x'; Priority = 'urgent' } | Out-Null } catch { $threw = $true }
Assert-That 'unknown priority throws' $threw

# ---- ConvertTo-TaskDocName -------------------------------------------------
Write-Host "`nConvertTo-TaskDocName"

Assert-That 'simple title' ((ConvertTo-TaskDocName 17 'Reconsider the task system') -ceq 'Task-17-Reconsider-The-Task-System') (ConvertTo-TaskDocName 17 'Reconsider the task system')
$long = ConvertTo-TaskDocName 5 'Wire [[Vault-MCP-Server]] auth & MCP/stdio transport for the remote client with a very long trailing explanation'
Assert-That 'link, &, /, MCP and long tail' ($long -ceq 'Task-5-Wire-Vault-MCP-Server-Auth-MCP-Stdio-Transport-For-The') $long
Assert-That 'title part capped at 60 chars' (($long.Length - 'Task-5-'.Length) -le 60)
Assert-That 'empty title yields bare id' ((ConvertTo-TaskDocName 3 '**~~**') -ceq 'Task-3')

# ---- File-based tests ------------------------------------------------------
$vaultRoot = Get-VaultRoot $PSScriptRoot
$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName '.vault-tasks-lib-tests'
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot

try {

Write-Host "`nGet-TaskFile"

$fixture = @(
    '---'
    'scope: personal'
    '---'
    '# Fixture Tasks'
    ''
    '## 🔔 Reminders'
    ''
    '- Halo releases 2026-07-28'
    '- [ ] Not a reminder'
    ''
    '## 🔥 Active'
    ''
    '- [ ] **Parent** - with kids | ➕ 2026-01-01'
    '  - two-space child'
    '    - [ ] Research'
    ''
    '      - six-space child after a blank'
    ''
    '- [/] Second | 🆔 7'
    ''
    '## 🧱 Blocked'
    '- [ ]'
    '## 📋 Backlog'
    '- [ ] Backlog item'
    '## Notes'
    '- [ ] Not a task, unknown section'
    '## 🗺️ Side Quests'
    '- [ ] Quest'
    '## ✅ Done'
    '- [x] Finished | ➕ 2026-01-01 ✅ 2026-01-02'
)

Run-Test 'file model: sections, tasks, children, reminders, problems, CRLF, scope' {
    New-TestFile 'Areas/Fix/Tasks.md' (($fixture -join "`r`n") + "`r`n")
    $m = Get-TaskFile -Path (Join-Path $testRoot 'Areas' 'Fix' 'Tasks.md') -VaultRoot $testRoot
    $names = ($m.Sections | ForEach-Object { if ($_.Name) { $_.Name } else { '?' } }) -join ','
    $cur = $m.Sections | Where-Object { $_.Name -eq 'Current' }
    $parent = $m.Tasks[0]
    $probs = ($m.Problems | ForEach-Object { "$($_.LineNumber):$($_.Message)" }) -join ' / '
    Assert-That 'sections in order'              ($names -eq 'Reminders,Current,Blocked,Backlog,?,SideQuests,Done') $names
    Assert-That 'Active maps to Current as legacy' ($cur.LegacyName -and $cur.Heading -eq '🔥 Active' -and $cur.LineNumber -eq 11 -and $cur.EndLine -eq 20) "$($cur | Out-String)"
    Assert-That 'CRLF detected'                  ($m.LineEnding -eq "`r`n")
    Assert-That 'scope read'                     ($m.Scope -eq 'personal')
    Assert-That 'Lines as read, no trailing empty' ($m.Lines.Count -eq $fixture.Count -and $m.Lines[0] -eq '---')
    Assert-That 'six tasks (nested, reminder, unknown-section excluded)' ($m.Tasks.Count -eq 6) (($m.Tasks | ForEach-Object Title) -join ',')
    Assert-That 'parent children at 2/4/6 spaces incl inner blank' ($parent.Children.Count -eq 4 -and $parent.Children[1] -eq '    - [ ] Research' -and $parent.Children[3] -eq '      - six-space child after a blank') ($parent.Children -join '|')
    Assert-That 'parent line and end'            ($parent.LineNumber -eq 13 -and $parent.EndLine -eq 17 -and $parent.Section -eq 'Current')
    Assert-That 'File is repo-relative with /'   ($parent.File -eq '.vault-tasks-lib-tests/Areas/Fix/Tasks.md' -or $parent.File -eq 'Areas/Fix/Tasks.md') $parent.File
    Assert-That 'second task has no children'    ($m.Tasks[1].Children.Count -eq 0 -and $m.Tasks[1].EndLine -eq 19 -and $m.Tasks[1].IdNumber -eq 7)
    Assert-That 'sections assigned'              ((($m.Tasks | ForEach-Object Section) -join ',') -eq 'Current,Current,Blocked,Backlog,SideQuests,Done')
    Assert-That 'one reminder'                   ($m.Reminders.Count -eq 1 -and $m.Reminders[0].Text -eq 'Halo releases 2026-07-28' -and $m.Reminders[0].LineNumber -eq 8)
    Assert-That 'problem: checkbox in reminders' ($probs -match '9:Checkbox line in the Reminders') $probs
    Assert-That 'problem: legacy Active'         ($probs -match '11:.*rename it to Current') $probs
    Assert-That 'problem: empty title'           ($probs -match '22:Checkbox line has an empty title') $probs
    Assert-That 'problem: unknown section'       ($probs -match "25:Unknown section '## Notes'") $probs
    $m.Problems.Count -eq 4
}

Run-Test 'section map: Current canonical, Sprint and Active legacy' {
    $c = Get-TaskSectionName '🔥 Current'
    $s = Get-TaskSectionName '🔥 Sprint'
    $a = Get-TaskSectionName 'Active'
    Assert-That 'Current maps, not legacy' ($c.Name -eq 'Current' -and -not $c.Legacy) "$($c | Out-String)"
    Assert-That 'Sprint maps to Current as legacy' ($s.Name -eq 'Current' -and $s.Legacy) "$($s | Out-String)"
    Assert-That 'Active maps to Current as legacy' ($a.Name -eq 'Current' -and $a.Legacy) "$($a | Out-String)"
    $true
}

Run-Test 'file model: LF, no frontmatter gives null scope' {
    New-TestFile 'Tasks.md' "# T`n`n## Current`n- [ ] a`n"
    $m = Get-TaskFile -Path (Join-Path $testRoot 'Tasks.md') -VaultRoot $testRoot
    $m.LineEnding -eq "`n" -and $null -eq $m.Scope -and $m.Tasks.Count -eq 1 -and $m.Problems.Count -eq 0 -and $m.Tasks[0].File -eq 'Tasks.md'
}

Run-Test 'file model: every real Tasks.md parses with no unexpected nulls' {
    $ok = $true
    foreach ($f in Get-TaskFiles -VaultRoot $worktreePath) {
        $m = Get-TaskFile -Path $f -VaultRoot $worktreePath
        $cbCount = @($m.Lines | Where-Object { $_ -match '^- \[.\]' }).Count
        if ($m.Tasks.Count + @($m.Problems | Where-Object { $_.Message -match 'Reminders|Unknown' }).Count -gt $cbCount) { $ok = $false }
        foreach ($t in $m.Tasks) { if ($null -eq $t.Title) { $ok = $false } }
    }
    $ok
}

Write-Host "`nSet-FileLines"

Run-Test 'Set-FileLines preserves CRLF and writes no BOM' {
    $p = Join-Path $testRoot 'out.md'
    Set-FileLines -Path $p -Lines @('a', '- [ ] b') -LineEnding "`r`n"
    (Get-TestFileContent 'out.md') -ceq "a`r`n- [ ] b`r`n" -and (Test-NoBom 'out.md')
}

Run-Test 'Set-FileLines round-trips a loaded file byte-for-byte' {
    $content = ($fixture -join "`r`n") + "`r`n"
    New-TestFile 'Tasks.md' $content
    $m = Get-TaskFile -Path (Join-Path $testRoot 'Tasks.md') -VaultRoot $testRoot
    Set-FileLines -Path $m.Path -Lines $m.Lines -LineEnding $m.LineEnding
    (Get-TestFileContent 'Tasks.md') -ceq $content
}

Write-Host "`nGet-TaskFiles / Get-NextTaskId"

Run-Test 'Get-TaskFiles scans the whole root with exclusions and -Path' {
    foreach ($rel in 'Tasks.md', 'Areas/A/Tasks.md', 'Projects/P/Sub/Tasks.md', 'Other/Deep/Tasks.md',
                     'Archive/Old/Tasks.md', 'Projects/P/Archive/Tasks.md', 'node_modules/x/Tasks.md',
                     '.claude/Tasks.md', '.obsidian/Tasks.md', 'bin/Tasks.md', 'Custom/Tasks.md', 'Areas/A/NotTasks.md') {
        New-TestFile $rel "## Current`n"
    }
    $rel = { param($list) (@(foreach ($x in $list) { if ($x) { $x.Substring($testRoot.Length + 1) -replace "\\", "/" } })) -join "," }
    $all = & $rel (Get-TaskFiles -VaultRoot $testRoot)
    $ext = & $rel (Get-TaskFiles -VaultRoot $testRoot -ExcludeFolders 'Custom')
    $sub = & $rel (Get-TaskFiles -VaultRoot $testRoot -Path 'Projects')
    $abs = & $rel (Get-TaskFiles -VaultRoot $testRoot -Path (Join-Path $testRoot 'Areas'))
    $arc = & $rel (Get-TaskFiles -VaultRoot $testRoot -Path 'Archive')
    $inc = & $rel (Get-TaskFiles -VaultRoot $testRoot -IncludeArchive)
    $sepOk = @(Get-TaskFiles -VaultRoot $testRoot -Path 'Areas')[0] -eq (Join-Path $testRoot 'Areas' 'A' 'Tasks.md')
    Assert-That 'default scan'        ($all -ceq 'Areas/A/Tasks.md,Custom/Tasks.md,Other/Deep/Tasks.md,Projects/P/Sub/Tasks.md,Tasks.md') $all
    Assert-That '-ExcludeFolders'     ($ext -ceq 'Areas/A/Tasks.md,Other/Deep/Tasks.md,Projects/P/Sub/Tasks.md,Tasks.md') $ext
    Assert-That '-Path relative'      ($sub -ceq 'Projects/P/Sub/Tasks.md') $sub
    Assert-That '-Path absolute'      ($abs -ceq 'Areas/A/Tasks.md') $abs
    Assert-That '-Path into excluded' ($arc -eq '') $arc
    Assert-That '-IncludeArchive'     ($inc -match 'Archive/Old/Tasks.md' -and $inc -match 'Projects/P/Archive/Tasks.md' -and $inc -notmatch 'node_modules') $inc
    Assert-That 'platform separator'  $sepOk
    $true
}

Run-Test 'Get-NextTaskId returns 1 with no IDs' {
    New-TestFile 'Areas/A/Tasks.md' "## Current`n- [ ] a`n"
    (Get-NextTaskId -VaultRoot $testRoot) -eq 1
}

Run-Test 'Get-NextTaskId: max across two files plus a Task-40 doc is 41' {
    New-TestFile 'Areas/A/Tasks.md' "## Current`n- [ ] a | 🆔 12`n- [ ] b | 🆔 x9`n"
    New-TestFile 'Projects/P/Tasks.md' "## Backlog`n- [ ] c | 🆔 33`n  - [ ] nested | 🆔 99`n## Notes`n- [ ] d | 🆔 98`n"
    New-TestFile 'Projects/P/Inbox/Task-40-Something.md' "# Something`n"
    (Get-NextTaskId -VaultRoot $testRoot) -eq 41
}

Run-Test 'Get-NextTaskId counts archived task docs and archived Tasks.md' {
    New-TestFile 'Areas/A/Tasks.md' "## Current`n- [ ] a | 🆔 2`n"
    New-TestFile 'Areas/A/Archive/Task-50-Old.md' "# Old`n"
    New-TestFile 'Archive/Proj/Tasks.md' "## Done`n- [x] z | 🆔 60`n"
    New-TestFile 'node_modules/Task-900-Junk.md' ''
    (Get-NextTaskId -VaultRoot $testRoot) -eq 61
}

} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
