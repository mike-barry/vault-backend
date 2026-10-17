# vault-tasks.ps1
# Shared parser, emitter, and file model for task lists kept as Obsidian Tasks plugin
# checkbox lines in per-context Tasks.md files. Dot-source it from any script that reads or
# edits tasks:
#   $_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
#   . (Join-Path $_skillDir '..' '_shared' 'vault-tasks.ps1')
#
# Model
#   A task is an indent-zero checkbox line ('- [c] ...', c any single char) inside a task
#   section ('##' heading: Current (legacy: Sprint, Active), Blocked, Backlog, Side Quests, Done) of a
#   file named Tasks.md. Indented and blank lines after it are its Children (its body), never
#   tasks themselves, and travel with it on a move. Indent-zero bullets under Reminders are
#   reminders. Queue is the section; status is the checkbox symbol.
#
#   Line grammar (canonical form, written by ConvertTo-TaskLine):
#     - [<sym>] <head><tags> | <fields>
#   head   = '**Title** - Text', or bare 'Title' when Text is empty; a wikilink title (a
#            promoted task) is never bolded ('[[Task-N-X]] - Text' when it has Text).
#   fields = priority, start, scheduled, due, id, created, done, cancelled, then any other
#            plugin fields (recurrence, depends-on, on-completion) verbatim. No ' | ' is
#            written when there are no fields.
#   Reading is lenient: fields are stripped from the END of the line in any order, the way
#   the Tasks plugin does it, and the ' | ' separator is optional and meaningless on read.
#
# Surgical-edit contract
#   Writers never regenerate a Tasks.md from the model. Every edit is: Get-TaskFile, change
#   specific entries of its .Lines (replace a line with ConvertTo-TaskLine output, insert or
#   remove a task line plus its Children by LineNumber/EndLine), then Set-FileLines with the
#   file's own .LineEnding. Anything the parser does not understand stays byte-for-byte.
#
# Portability
#   Assumes no folder layout: task files are found by name anywhere under the repo root,
#   skipping $TaskScanExcludedFolders. Lift this file into another repo together with:
#     vault-common.ps1      - $Utf8NoBom, Format-VaultRoot, Get-VaultRoot, Resolve-VaultPath,
#                             Get-PrunedFiles, ConvertTo-TitleSlug
#     vault-frontmatter.ps1 - Get-FrontmatterField (it dot-sources vault-common.ps1 itself)
#   Where a task doc is created is the caller's decision; nothing here chooses a folder.

. (Join-Path $PSScriptRoot 'vault-frontmatter.ps1')

# Folder names never descended into when scanning for task files and task docs.
$TaskScanExcludedFolders = @('Archive', '.git', '.claude', '.vault', '.obsidian', 'node_modules', '.venv', 'bin', 'obj')

# ---------------------------------------------------------------------------
# Field vocabulary (built from code points so this file stays ASCII)
# ---------------------------------------------------------------------------

function _TaskEmoji([int]$cp) { [char]::ConvertFromUtf32($cp) }

$script:TaskPriorityEmoji = [ordered]@{
    highest = _TaskEmoji 0x1F53A
    high    = _TaskEmoji 0x23EB
    medium  = _TaskEmoji 0x1F53C
    low     = _TaskEmoji 0x1F53D
    lowest  = _TaskEmoji 0x23EC
}
# Canonical date emoji per property, in emit order.
$script:TaskDateEmoji = [ordered]@{
    Start         = _TaskEmoji 0x1F6EB
    Scheduled     = _TaskEmoji 0x23F3
    Due           = _TaskEmoji 0x1F4C5
    Created       = _TaskEmoji 0x2795
    DoneDate      = _TaskEmoji 0x2705
    CancelledDate = _TaskEmoji 0x274C
}
# Alternate spellings the plugin also accepts on read (emitted in canonical form).
$script:TaskDateAliases = @{
    (_TaskEmoji 0x1F4C6) = 'Due'
    (_TaskEmoji 0x1F5D3) = 'Due'
    (_TaskEmoji 0x231B)  = 'Scheduled'
}
$script:TaskIdEmoji         = _TaskEmoji 0x1F194
$script:TaskDependsEmoji    = _TaskEmoji 0x26D4
$script:TaskRecurEmoji      = _TaskEmoji 0x1F501
$script:TaskOnCompleteEmoji = _TaskEmoji 0x1F3C1

function _TaskAlt([string[]]$s) { '(?:' + (($s | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')' }

$script:TaskAllFieldEmoji = @($script:TaskPriorityEmoji.Values) + @($script:TaskDateEmoji.Values) +
    @($script:TaskDateAliases.Keys) + @($script:TaskIdEmoji, $script:TaskDependsEmoji, $script:TaskRecurEmoji, $script:TaskOnCompleteEmoji)

# '️?' admits the optional emoji variation selector after each field emoji.
$script:TaskRx = @{
    Checkbox   = [regex]'^- \[(.)\](?:\s(.*))?$'
    Priority   = [regex]('(' + (_TaskAlt @($script:TaskPriorityEmoji.Values)) + ')️?\s*$')
    Date       = [regex]('(' + (_TaskAlt (@($script:TaskDateEmoji.Values) + @($script:TaskDateAliases.Keys))) + ')️?\s*(\d{4}-\d{2}-\d{2})\s*$')
    Id         = [regex]([regex]::Escape($script:TaskIdEmoji) + '️?\s*([A-Za-z0-9_-]+)\s*$')
    Depends    = [regex]([regex]::Escape($script:TaskDependsEmoji) + '️?\s*([A-Za-z0-9_-]+(?:[ ,]+[A-Za-z0-9_-]+)*)\s*$')
    OnComplete = [regex]([regex]::Escape($script:TaskOnCompleteEmoji) + '️?\s*([A-Za-z]+)\s*$')
    Recur      = [regex]([regex]::Escape($script:TaskRecurEmoji) + '️?(?:(?!' + (_TaskAlt $script:TaskAllFieldEmoji) + ').)*$')
    TrailTag   = [regex]'(?<!\S)#([\w/-]+)\s*$'
    Tag        = [regex]'(?<!\S)#([\w/-]+)'
    Protected  = [regex]'\[\[.*?\]\]|`[^`]*`|\]\((?:\\.|[^)\\])*\)|<[^>\s]+>|https?://\S+'
    Bold       = [regex]'^\*\*(.+?)\*\*(.*)$'
    LinkHead   = [regex]'^(\[\[[^\[\]]+\]\])(?:\s+-\s+(.*))?$'
    WikiLink   = [regex]'^\[\[([^\]|]+)(?:\|[^\]]*)?\]\]$'
    Heading    = [regex]'^##(?!#)\s*(.*?)\s*$'
    Fence      = [regex]'^\s*(```|~~~)'
}

# Map a checkbox symbol to its status name: todo, in-progress, done, cancelled, or other.
function ConvertTo-TaskStatus {
    param([AllowEmptyString()][string]$Symbol)
    switch -CaseSensitive ($Symbol) {
        ' '     { return 'todo' }
        '/'     { return 'in-progress' }
        'x'     { return 'done' }
        'X'     { return 'done' }
        '-'     { return 'cancelled' }
        default { return 'other' }
    }
}

# Read a property from a hashtable or PSObject; $null when absent (StrictMode-safe).
function _TaskProp($Obj, [string]$Name) {
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $null
    }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

# A tag token is '#' + [\w/-]+ preceded by whitespace or line start, and not all digits (so
# 'issue #10' stays text, as Obsidian treats it).
function _Test-TagToken([string]$Name) { return $Name -notmatch '^\d+$' }

function _Find-Key($Map, [string]$Value) {
    foreach ($e in $Map.GetEnumerator()) { if ($e.Value -eq $Value) { return $e.Key } }
    return $null
}

# ---------------------------------------------------------------------------
# Line parse / emit
# ---------------------------------------------------------------------------

# Parse one line. Returns $null unless it is an indent-zero checkbox line; otherwise a
# PSCustomObject: Symbol, Status, Id, IdNumber, Title, Text, Tags, Link, Promoted, Priority,
# Start, Scheduled, Due, Created, DoneDate, CancelledDate, Extra, Raw. Free text never makes
# it fail; a bare checkbox yields an empty Title. A field emoji repeated on one line keeps
# the rightmost value in its property and preserves the others verbatim in Extra.
function ConvertFrom-TaskLine {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)
    $m = $script:TaskRx.Checkbox.Match($Line.TrimEnd("`r", "`n"))
    if (-not $m.Success) { return $null }
    $symbol = $m.Groups[1].Value
    $rest   = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { '' }

    $f = @{ Priority = $null; Start = $null; Scheduled = $null; Due = $null; Created = $null; DoneDate = $null; CancelledDate = $null; Id = $null }
    $extra     = [System.Collections.Generic.List[string]]::new()   # collected right-to-left
    $trailTags = [System.Collections.Generic.List[string]]::new()   # collected right-to-left

    # Strip trailing fields until the end of the line is no longer one.
    while ($true) {
        $rest = $rest.TrimEnd()
        if (-not $rest) { break }

        $mm = $script:TaskRx.Priority.Match($rest)
        if ($mm.Success) {
            $name = _Find-Key $script:TaskPriorityEmoji $mm.Groups[1].Value
            if ($null -eq $f.Priority) { $f.Priority = $name } else { $extra.Add($mm.Value.Trim()) }
            $rest = $rest.Substring(0, $mm.Index); continue
        }
        $mm = $script:TaskRx.Date.Match($rest)
        if ($mm.Success) {
            $emo  = $mm.Groups[1].Value
            $prop = if ($script:TaskDateAliases.ContainsKey($emo)) { $script:TaskDateAliases[$emo] } else { _Find-Key $script:TaskDateEmoji $emo }
            if ($null -eq $f[$prop]) { $f[$prop] = $mm.Groups[2].Value } else { $extra.Add($mm.Value.Trim()) }
            $rest = $rest.Substring(0, $mm.Index); continue
        }
        $mm = $script:TaskRx.Id.Match($rest)
        if ($mm.Success) {
            if ($null -eq $f.Id) { $f.Id = $mm.Groups[1].Value } else { $extra.Add($mm.Value.Trim()) }
            $rest = $rest.Substring(0, $mm.Index); continue
        }
        $matched = $false
        foreach ($rx in @($script:TaskRx.Depends, $script:TaskRx.OnComplete, $script:TaskRx.Recur)) {
            $mm = $rx.Match($rest)
            if ($mm.Success) {
                $extra.Add($mm.Value.Trim())
                $rest = $rest.Substring(0, $mm.Index)
                $matched = $true
                break
            }
        }
        if ($matched) { continue }
        # A tag between or after fields (the plugin allows it); kept as a tag.
        $mm = $script:TaskRx.TrailTag.Match($rest)
        if ($mm.Success -and (_Test-TagToken $mm.Groups[1].Value)) {
            $trailTags.Add($mm.Groups[1].Value)
            $rest = $rest.Substring(0, $mm.Index); continue
        }
        break
    }
    $extra.Reverse()
    $trailTags.Reverse()

    # Pull inline tags out of the free text, skipping wikilinks, link targets, code spans,
    # autolinks, and bare URLs.
    $protected = @(foreach ($pm in $script:TaskRx.Protected.Matches($rest)) { , @($pm.Index, ($pm.Index + $pm.Length)) })
    $tags = [System.Collections.Generic.List[string]]::new()
    $sb   = [System.Text.StringBuilder]::new()
    $pos  = 0
    foreach ($tm in $script:TaskRx.Tag.Matches($rest)) {
        $inside = $false
        foreach ($r in $protected) { if ($tm.Index -ge $r[0] -and $tm.Index -lt $r[1]) { $inside = $true; break } }
        if ($inside -or -not (_Test-TagToken $tm.Groups[1].Value)) { continue }
        $cut = $tm.Index
        while ($cut -gt $pos -and [char]::IsWhiteSpace($rest[$cut - 1])) { $cut-- }
        [void]$sb.Append($rest.Substring($pos, $cut - $pos))
        $pos = $tm.Index + $tm.Length
        $tags.Add($tm.Groups[1].Value)
    }
    [void]$sb.Append($rest.Substring($pos))
    foreach ($t in $trailTags) { $tags.Add($t) }

    $free = $sb.ToString().Trim()
    if ($free.EndsWith('|')) { $free = $free.Substring(0, $free.Length - 1).TrimEnd() }

    $title = $free; $text = ''; $link = $null; $promoted = $false
    $bm = $script:TaskRx.Bold.Match($free)
    $lm = $script:TaskRx.LinkHead.Match($free)
    if ($bm.Success) {
        $title = $bm.Groups[1].Value
        $text  = ($bm.Groups[2].Value -replace '^\s+-\s+', '').Trim()
    } elseif ($lm.Success) {
        $title = $lm.Groups[1].Value
        $text  = if ($lm.Groups[2].Success) { $lm.Groups[2].Value.Trim() } else { '' }
    }
    $wm = $script:TaskRx.WikiLink.Match($title)
    if ($wm.Success) {
        $target   = ($wm.Groups[1].Value -split '#', 2)[0]
        $link     = ($target -split '/')[-1]
        $promoted = $true
    }

    $idNumber = $null
    if ($f.Id -and $f.Id -match '^\d+$') {
        $n = 0
        if ([int]::TryParse($f.Id, [ref]$n)) { $idNumber = $n }
    }

    return [PSCustomObject]@{
        Symbol        = $symbol
        Status        = ConvertTo-TaskStatus $symbol
        Id            = $f.Id
        IdNumber      = $idNumber
        Title         = $title
        Text          = $text
        Tags          = [string[]]$tags.ToArray()
        Link          = $link
        Promoted      = $promoted
        Priority      = $f.Priority
        Start         = $f.Start
        Scheduled     = $f.Scheduled
        Due           = $f.Due
        Created       = $f.Created
        DoneDate      = $f.DoneDate
        CancelledDate = $f.CancelledDate
        Extra         = [string[]]$extra.ToArray()
        Raw           = $Line
    }
}

# Emit the canonical line for a task: a PSCustomObject or hashtable using ConvertFrom-
# TaskLine's property names, absent properties treated as empty. Symbol wins over Status;
# with neither the task is written as todo. Throws on an unknown Priority name.
function ConvertTo-TaskLine {
    param([Parameter(Mandatory)]$Task)
    $sym = _TaskProp $Task 'Symbol'
    if ($null -eq $sym -or "$sym".Length -ne 1) {
        $sym = switch (_TaskProp $Task 'Status') { 'in-progress' { '/' } 'done' { 'x' } 'cancelled' { '-' } default { ' ' } }
    }
    $title  = [string](_TaskProp $Task 'Title')
    $text   = [string](_TaskProp $Task 'Text')
    $isLink = $script:TaskRx.WikiLink.IsMatch($title)
    $head = if (-not $text) { $title } elseif ($isLink) { "$title - $text" } else { "**$title** - $text" }
    foreach ($t in @(_TaskProp $Task 'Tags')) { if ($t) { $head += ' #' + ([string]$t).TrimStart('#') } }
    $head = $head.Trim()

    $fields = [System.Collections.Generic.List[string]]::new()
    $prio = _TaskProp $Task 'Priority'
    if ($prio) {
        if (-not $script:TaskPriorityEmoji.Contains([string]$prio)) { throw "Unknown task priority '$prio'" }
        $fields.Add($script:TaskPriorityEmoji[[string]$prio])
    }
    foreach ($k in 'Start', 'Scheduled', 'Due') { $v = _TaskProp $Task $k; if ($v) { $fields.Add("$($script:TaskDateEmoji[$k]) $v") } }
    $id = _TaskProp $Task 'Id'
    if ($null -ne $id -and "$id" -ne '') { $fields.Add("$($script:TaskIdEmoji) $id") }
    foreach ($k in 'Created', 'DoneDate', 'CancelledDate') { $v = _TaskProp $Task $k; if ($v) { $fields.Add("$($script:TaskDateEmoji[$k]) $v") } }
    foreach ($e in @(_TaskProp $Task 'Extra')) { if ($e) { $fields.Add([string]$e) } }

    $out = "- [$sym]"
    if ($head) { $out += " $head" }
    if ($fields.Count) { $out += ' | ' + ($fields -join ' ') }
    return $out
}

# ---------------------------------------------------------------------------
# File model
# ---------------------------------------------------------------------------

# Map a '##' heading's text to @{ Name; Legacy } by keyword, ignoring case, emoji, spacing,
# and punctuation. Name is $null for an unknown section; Legacy is true for 'Sprint' and 'Active'.
function Get-TaskSectionName {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Heading)
    $key = ($Heading -replace '[^\p{L}]', '').ToLowerInvariant()
    switch ($key) {
        'reminders'  { return @{ Name = 'Reminders';  Legacy = $false } }
        'current'    { return @{ Name = 'Current';    Legacy = $false } }
        'sprint'     { return @{ Name = 'Current';    Legacy = $true } }
        'active'     { return @{ Name = 'Current';    Legacy = $true } }
        'blocked'    { return @{ Name = 'Blocked';    Legacy = $false } }
        'backlog'    { return @{ Name = 'Backlog';    Legacy = $false } }
        'sidequests' { return @{ Name = 'SideQuests'; Legacy = $false } }
        'done'       { return @{ Name = 'Done';       Legacy = $false } }
    }
    return @{ Name = $null; Legacy = $false }
}

# Repo-relative path with '/' separators, or the '/'-normalized absolute path when $Path is
# not under $Root.
function _Get-RelPath([string]$Root, [string]$Path) {
    $r = Format-VaultRoot $Root
    if ($Path.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) { return ($Path.Substring($r.Length) -replace '\\', '/') }
    if ((Format-VaultRoot $Path) -ieq $r) { return '' }
    return ($Path -replace '\\', '/')
}

# Load and model one task file (see the header). -VaultRoot defaults to the git repo holding
# the file and only feeds each task's repo-relative File. Lines excludes the empty element
# after the final newline; Set-FileLines puts that newline back.
function Get-TaskFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$VaultRoot
    )
    $abs = (Resolve-Path -LiteralPath $Path).Path
    if (-not $VaultRoot) {
        try { $VaultRoot = Get-VaultRoot -StartPath (Split-Path $abs -Parent) } catch { $VaultRoot = Split-Path $abs -Parent }
    }
    $rel = _Get-RelPath $VaultRoot $abs

    $content = [System.IO.File]::ReadAllText($abs, [System.Text.Encoding]::UTF8)
    $eol = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [string[]]@()
    if ($content.Length) {
        $lines = [string[]]($content -split "`r?`n")
        if ($lines[-1] -eq '') { $lines = [string[]]@($lines | Select-Object -SkipLast 1) }
    }
    $scope = if ($content) { Get-FrontmatterField -Content $content -Field 'scope' } else { $null }

    $sections  = [System.Collections.Generic.List[object]]::new()
    $tasks     = [System.Collections.Generic.List[object]]::new()
    $reminders = [System.Collections.Generic.List[object]]::new()
    $problems  = [System.Collections.Generic.List[object]]::new()
    $taskSections = @('Current', 'Blocked', 'Backlog', 'SideQuests', 'Done')
    function AddProblem([int]$n, [string]$msg) { $problems.Add([PSCustomObject]@{ LineNumber = $n; Message = $msg }) }

    # Skip a leading frontmatter block.
    $start = 0
    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
        for ($j = 1; $j -lt $lines.Count; $j++) { if ($lines[$j].Trim() -eq '---') { $start = $j + 1; break } }
    }

    $current = $null
    $inFence = $false
    for ($i = $start; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $ln   = $i + 1
        if ($script:TaskRx.Fence.IsMatch($line)) { $inFence = -not $inFence; continue }
        if ($inFence) { continue }

        $hm = $script:TaskRx.Heading.Match($line)
        if ($hm.Success) {
            if ($current) { $current.EndLine = $ln - 1 }
            $heading = $hm.Groups[1].Value
            $map = Get-TaskSectionName $heading
            $current = [PSCustomObject]@{ Name = $map.Name; Heading = $heading; LegacyName = $map.Legacy; LineNumber = $ln; EndLine = $lines.Count }
            $sections.Add($current)
            if (-not $map.Name) { AddProblem $ln "Unknown section '## $heading'; lines under it are not read as tasks" }
            elseif ($map.Legacy) { AddProblem $ln "Section '## $heading' uses the legacy name $(($heading -replace '[^\p{L}]', '')); rename it to Current" }
            continue
        }
        if (-not $current -or -not $current.Name) { continue }

        $task = ConvertFrom-TaskLine -Line $line
        if ($current.Name -eq 'Reminders') {
            if ($task) { AddProblem $ln 'Checkbox line in the Reminders section; reminders are plain bullets' }
            elseif ($line -match '^[-*+]\s+(.*)$') { $reminders.Add([PSCustomObject]@{ LineNumber = $ln; Text = $Matches[1] }) }
            continue
        }
        if (-not $task -or $taskSections -notcontains $current.Name) { continue }

        # Children: the following indented or blank lines, trailing blanks trimmed off.
        $k = $i + 1
        while ($k -lt $lines.Count -and ($lines[$k] -eq '' -or $lines[$k] -match '^\s')) { $k++ }
        $last = $k - 1
        while ($last -gt $i -and $lines[$last].Trim() -eq '') { $last-- }
        $children = [string[]]@()
        if ($last -gt $i) { $children = [string[]]$lines[($i + 1)..$last] }

        $task | Add-Member -NotePropertyMembers ([ordered]@{
            File = $rel; LineNumber = $ln; Section = $current.Name; Children = $children; EndLine = $last + 1
        })
        $tasks.Add($task)
        if (-not $task.Title) { AddProblem $ln 'Checkbox line has an empty title' }
        $i = $last
    }

    return [PSCustomObject]@{
        Path       = $abs
        File       = $rel
        Scope      = $scope
        LineEnding = $eol
        Lines      = $lines
        Sections   = $sections.ToArray()
        Tasks      = $tasks.ToArray()
        Reminders  = $reminders.ToArray()
        Problems   = $problems.ToArray()
    }
}

# Write a whole file as UTF-8 without BOM: lines joined by $LineEnding plus a trailing one
# (an empty array writes an empty file). The only writer the task verbs use; see the
# surgical-edit contract in the header.
function Set-FileLines {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [ValidateSet("`n", "`r`n")][string]$LineEnding = "`n"
    )
    $text = if ($Lines.Count) { ($Lines -join $LineEnding) + $LineEnding } else { '' }
    [System.IO.File]::WriteAllText($Path, $text, $Utf8NoBom)
}

# ---------------------------------------------------------------------------
# Discovery and identity
# ---------------------------------------------------------------------------

# True when any segment of $RelPath is in $Names (case-insensitive).
function _Test-ExcludedSegment([string]$RelPath, [string[]]$Names) {
    foreach ($seg in ($RelPath -split '[/\\]')) {
        if ($seg -and @($Names | Where-Object { $_ -ieq $seg }).Count) { return $true }
    }
    return $false
}

# Every Tasks.md under the repo root, or under -Path (repo-relative or absolute), skipping
# any folder named in $TaskScanExcludedFolders or -ExcludeFolders. -IncludeArchive walks
# Archive folders too. Returns sorted absolute paths.
function Get-TaskFiles {
    param(
        [Parameter(Mandatory)][string]$VaultRoot,
        [string]$Path,
        [string[]]$ExcludeFolders = @(),
        [switch]$IncludeArchive
    )
    $ex = @($TaskScanExcludedFolders) + @($ExcludeFolders)
    if ($IncludeArchive) { $ex = @($ex | Where-Object { $_ -ne 'Archive' }) }
    $root = $VaultRoot
    if ($Path) {
        $root = Resolve-VaultPath -VaultRoot (Format-VaultRoot $VaultRoot) -Path $Path
        if (_Test-ExcludedSegment (_Get-RelPath $VaultRoot $root) $ex) { return [string[]]@() }
    }
    return [string[]]@(Get-PrunedFiles -Root $root -Filter 'Tasks.md' -ExcludeFolderNames $ex |
        Where-Object { [System.IO.Path]::GetFileName($_) -eq 'Tasks.md' })
}

# Next free global task ID: 1 + the highest numeric ID on any task line or in any
# 'Task-<N>-*.md' filename in the repo, with the same folder exclusions as Get-TaskFiles
# except Archive, which is scanned: done tasks' docs are archived, and an archived project
# keeps its Tasks.md, so their numbers must still count. Returns 1 when none exist.
function Get-NextTaskId {
    param(
        [Parameter(Mandatory)][string]$VaultRoot,
        [string[]]$ExcludeFolders = @()
    )
    $max = 0
    foreach ($f in Get-TaskFiles -VaultRoot $VaultRoot -ExcludeFolders $ExcludeFolders -IncludeArchive) {
        foreach ($t in (Get-TaskFile -Path $f -VaultRoot $VaultRoot).Tasks) {
            if ($null -ne $t.IdNumber -and $t.IdNumber -gt $max) { $max = $t.IdNumber }
        }
    }
    $ex = @(@($TaskScanExcludedFolders) + @($ExcludeFolders) | Where-Object { $_ -ne 'Archive' })
    foreach ($doc in Get-PrunedFiles -Root $VaultRoot -Filter 'Task-*.md' -ExcludeFolderNames $ex) {
        if ([System.IO.Path]::GetFileName($doc) -match '^Task-(\d+)-.*\.md$') {
            $n = 0
            if ([int]::TryParse($Matches[1], [ref]$n) -and $n -gt $max) { $max = $n }
        }
    }
    return $max + 1
}

# Filename stem for a promoted task's doc: 'Task-<Id>-<Title-Case-With-Hyphens>', no
# extension, title part capped at 60 characters on a word boundary. Says nothing about the
# folder; the caller decides where the doc lives.
function ConvertTo-TaskDocName {
    param(
        [Parameter(Mandatory)][int]$Id,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title
    )
    $slug = ConvertTo-TitleSlug -Text $Title -MaxLength 60
    if ($slug) { return "Task-$Id-$slug" }
    return "Task-$Id"
}
