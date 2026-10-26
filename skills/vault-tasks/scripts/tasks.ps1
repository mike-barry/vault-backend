# tasks.ps1
# Verb script for the vault-tasks skill: lists, checks, and edits task lines in Tasks.md
# files through the shared parser/emitter in _shared/vault-tasks.ps1. Every run writes one
# JSON document to stdout and nothing else; an error writes one message to stderr and exits
# 1. Judgment (routing a task to a file, wording, archiving a done task's doc) stays in the
# skill's prose - not here.
#
# Usage (array parameters take a real array, or one string delimited by commas - by newlines
# for -Children and -AddChild - so 'pwsh -File tasks.ps1 -Tags a,b' works as well):
#   .\tasks.ps1 -Action list     [-Path <file|folder>] [-Section <name[]>] [-Status <name[]>] [-Tag <tag[]>] [-Id <int[]>]
#   .\tasks.ps1 -Action check    [-Path <file|folder>]
#   .\tasks.ps1 -Action groups   [-Path <file|folder>]
#   .\tasks.ps1 -Action add     -Path <Tasks.md|folder> -Title <text> [-Section <name>] [-Status <name>] [-Text <text>]
#                                [-Tags <tag[]>] [-Priority <name>] [-Start|-Scheduled|-Due <date>] [-Children <text[]>]
#   .\tasks.ps1 -Action update   -Id <int> [-Title] [-Text] [-AddTag <tag[]>] [-RemoveTag <tag[]>] [-Priority]
#                                [-Start|-Scheduled|-Due <date|none>] [-Status] [-Section] [-AddChild <text[]>]
#   .\tasks.ps1 -Action promote  -Id <int> [-Title <text>] [-Intro <text>]
#   .\tasks.ps1 -Action done     -Id <int> [-Date <date>]
#   .\tasks.ps1 -Action cancel   -Id <int> [-Date <date>]
#   .\tasks.ps1 -Action prune    [-Path <file|folder>] [-Days <int>] [-Apply]
#   .\tasks.ps1 -Action backfill [-Path <file|folder>]
#   .\tasks.ps1 -Action renumber [-Id <int> [-Path <file|folder>]] [-Against <git-ref>] [-SkipPromoted] [-Apply]
#
# Verbs
#   list      task objects matching the filters, files sorted by path, lines top to bottom
#   check     { File, LineNumber, Code, Message } problems; exit 0 whether or not any exist.
#             Status is independent of queue ([/] is valid in any non-Done section); the one
#             constraint is that [x] and [-] live only in Done (code DoneOutsideDone)
#   groups    { Group, Open, Closed, Files, Views } per group/<name> tag, sorted by Group.
#             Open counts todo + in-progress, Closed done + cancelled; Files are the
#             Tasks.md files holding a tagged task. -Path scopes the counted files only:
#             Views is always repo-wide - every View-*.md outside excluded and Archive
#             folders whose text has #group/<Group> (not followed by a tag character)
#   add       stamps the next ID and created=today; inserts at the top of the section
#   update    rewrites the task's line; -Section moves the line and its children
#   (update, promote, done, and cancel also stamp a missing ID and created date on the line
#   they rewrite; list, check, groups, and prune never change a line)
#   promote   creates Task-<Id>-<Title>.md from templates/Task-Template.md (H1 in Title Case,
#             intro capitalized); the line becomes the link
#   done      [x] + done date (-Date, default today; never in the future); the line otherwise
#             unchanged, block moved to the top of Done
#   cancel    [-] + cancelled date, otherwise as done
#   prune     Done items older than -Days (default 7); preview unless -Apply
#   backfill  stamps a missing ID and created date on every task line
#   renumber  { OldId, NewId, File, LineNumber, Reason, DocRename, Skipped } per line moved
#             off a duplicated ID (every DuplicateId group, or just -Id); one line per ID
#             keeps it, the rest take consecutive IDs from the next free one. Preview
#             unless -Apply. Keeper: with -Against, a line is published when its file at
#             that ref has a task line with the ID (several in one file match by title),
#             and published lines keep it over unpublished ones; otherwise, or when all or
#             none are published, the earliest created date, then path and line order.
#             -Path (with -Id) instead renumbers the occurrences under it, refusing when
#             that would leave none on the ID. Only the ID changes: a promoted line keeps
#             its [[Task-<old>-...]] title and DocRename { OldPath, NewPath } names the doc
#             rename for the caller (a missing doc: the link is rewritten, DocRename null);
#             -SkipPromoted leaves those lines alone, Skipped true and NewId null
#   Sections: Current, Blocked, Backlog, SideQuests (or 'Side Quests'), Done, Reminders.
#   Statuses: todo, in-progress, done, cancelled. Priorities: highest, high, medium, low,
#   lowest, none. Dates: yyyy-MM-dd, or 'none' to clear; "today" is local time.
#
# Surgical-edit rule
#   Each write loads the file with Get-TaskFile, replaces, inserts, or removes specific
#   entries of its Lines, and writes back with Set-FileLines in the file's own line ending.
#   A file is never regenerated from the parsed model; untouched lines stay byte-identical.
#
# Portability rule
#   Assumes only that task files are named Tasks.md, that sections use the canonical
#   headings, and that a task doc goes in an Inbox/ folder beside its Tasks.md when one
#   exists, otherwise beside the Tasks.md. No Projects/, Areas/, or frontmatter convention.
#   git is run only by renumber -Against; everything else is file-only.
#   -VaultRootOverride redirects the repo root (unit tests).

param(
    [Parameter(Mandatory)]
    [ValidateSet('list', 'check', 'groups', 'add', 'update', 'promote', 'done', 'cancel', 'prune', 'backfill', 'renumber')]
    [string]$Action,
    # Scope for list, check, groups, prune, backfill (a Tasks.md or a folder); the target
    # Tasks.md or folder for add; the occurrences to renumber for renumber -Id.
    [string]$Path,
    # Array parameters also take one delimited string, so they work under 'pwsh -File':
    # -Section, -Status, -Tag, -Id, -Tags, -AddTag, -RemoveTag split on commas (pieces
    # trimmed, empties dropped); -Children and -AddChild split on newlines, so a child may
    # contain commas.
    [string[]]$Section,
    [string[]]$Status,
    [string[]]$Tag,
    [string[]]$Id,
    [AllowEmptyString()][string]$Title,
    [AllowEmptyString()][string]$Text,
    [string[]]$Tags,
    [string]$Priority,
    [string]$Start,
    [string]$Scheduled,
    [string]$Due,
    # Done or cancelled date for done and cancel; defaults to today.
    [string]$Date,
    [string[]]$Children,
    [string[]]$AddTag,
    [string[]]$RemoveTag,
    [string[]]$AddChild,
    [AllowEmptyString()][string]$Intro,
    [int]$Days = 7,
    [switch]$Apply,
    # Git ref renumber compares against to find published lines (e.g. '@{u}').
    [string]$Against,
    [switch]$SkipPromoted,
    # Override the vault root; used by unit tests to redirect to a temporary worktree.
    [string]$VaultRootOverride
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Bound = $PSBoundParameters

$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-tasks.ps1')

try { [Console]::OutputEncoding = $Utf8NoBom } catch { }

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

# Flatten an array parameter: split each element on $Pattern, trim, drop empties.
function Split-Param($Values, [string]$Pattern, [switch]$NoTrim) {
    $out = foreach ($v in @($Values)) {
        if ($null -eq $v) { continue }
        foreach ($piece in ([string]$v -split $Pattern)) {
            $x = if ($NoTrim) { $piece.TrimEnd() } else { $piece.Trim() }
            if ($x.Trim()) { $x }
        }
    }
    return [string[]]@($out)
}
foreach ($n in 'Section', 'Status', 'Tag', 'Tags', 'AddTag', 'RemoveTag') {
    if ($PSBoundParameters.ContainsKey($n)) { Set-Variable -Name $n -Value (Split-Param (Get-Variable $n -ValueOnly) ',') }
}
foreach ($n in 'Children', 'AddChild') {
    if ($PSBoundParameters.ContainsKey($n)) { Set-Variable -Name $n -Value (Split-Param (Get-Variable $n -ValueOnly) '\r?\n' -NoTrim) }
}
$IdList = [int[]]@(foreach ($x in (Split-Param $Id ',')) {
    $n = 0
    if (-not [int]::TryParse($x, [ref]$n)) { Fail "Invalid -Id '$x'. IDs are integers" }
    $n
})

# ---------------------------------------------------------------------------
# Argument helpers
# ---------------------------------------------------------------------------

$Today    = (Get-Date).ToString('yyyy-MM-dd')
$TaskLink = '^Task-\d+(?:-|$)'   # a promoted line's link names a task doc only when it matches

function Get-SectionKey([string]$Name) {
    switch (($Name -replace '[\s_-]', '').ToLowerInvariant()) {
        'current'    { return 'Current' }
        'blocked'    { return 'Blocked' }
        'backlog'    { return 'Backlog' }
        'sidequests' { return 'SideQuests' }
        'done'       { return 'Done' }
        'reminders'  { return 'Reminders' }
    }
    Fail "Unknown section '$Name'. Use one of: Current, Blocked, Backlog, SideQuests, Done, Reminders"
}

function Get-StatusKey([string]$Name) {
    $n = $Name.ToLowerInvariant()
    if (@('todo', 'in-progress', 'done', 'cancelled') -contains $n) { return $n }
    Fail "Unknown status '$Name'. Use one of: todo, in-progress, done, cancelled"
}

function Get-PriorityKey([string]$Name) {
    $n = $Name.ToLowerInvariant()
    if (@('highest', 'high', 'medium', 'low', 'lowest', 'none') -contains $n) { return $n }
    Fail "Unknown priority '$Name'. Use one of: highest, high, medium, low, lowest, none"
}

# 'none' -> '' (clear); a yyyy-MM-dd date passes through; anything else is an error.
function Get-DateValue([string]$ParamName, [string]$Value) {
    if ($Value -ieq 'none') { return '' }
    $d = [datetime]::MinValue
    if ($Value -match '^\d{4}-\d{2}-\d{2}$' -and
        [datetime]::TryParseExact($Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) {
        return $Value
    }
    Fail "Invalid -$ParamName '$Value'. Use yyyy-MM-dd or none"
}

function Get-TagValue([string]$Value) {
    $t = $Value.Trim().TrimStart('#')
    if ($t -notmatch '^[\w/-]+$' -or $t -match '^\d+$') { Fail "Invalid tag '$Value'. Tags are letters, digits, _, -, / and not all digits" }
    return $t
}

function Assert-OneLine([string]$Name, [string]$Value) {
    if ($Value -match "[`r`n]") { Fail "-$Name must be a single line" }
}

function Get-SingleId {
    if (-not $script:Bound.ContainsKey('Id')) { Fail "-Action $Action requires -Id" }
    if ($IdList.Count -ne 1) { Fail "-Action $Action takes exactly one -Id" }
    return $IdList[0]
}

# Title Case as the vault writes H1s: the first letter of every whitespace-separated word
# is upper-cased (after leading '(' '"' or quote marks) and the rest is left as typed;
# words inside a code span and wikilink words are left alone.
function ConvertTo-TitleCase([string]$Value) {
    $inCode = $false
    $words = foreach ($w in ($Value -split ' ')) {
        $startsCode = $w.StartsWith('`')
        $out = $w
        if (-not $inCode -and -not $startsCode -and -not $w.StartsWith('[[')) {
            $m = [regex]::Match($w, '^([("''' + [char]0x2018 + [char]0x201C + ']*)(\p{Ll})')
            if ($m.Success) { $out = $m.Groups[1].Value + $m.Groups[2].Value.ToUpperInvariant() + $w.Substring($m.Length) }
        }
        if ((([regex]::Matches($w, '`')).Count % 2) -eq 1) { $inCode = -not $inCode }
        $out
    }
    return (@($words) -join ' ')
}

# Upper-case the first character when it is a letter.
function ConvertTo-SentenceStart([string]$Value) {
    if ($Value -and [char]::IsLower($Value[0])) { return $Value.Substring(0, 1).ToUpperInvariant() + $Value.Substring(1) }
    return $Value
}

# Stamp a missing ID and created date on a task being rewritten (write verbs backfill the
# line they touch).
function Add-MissingStamps($Fields) {
    if (-not $Fields.Id) { $Fields.Id = [string](Get-NextTaskId -VaultRoot $VaultRoot) }
    if (-not $Fields.Created) { $Fields.Created = $Today }
}

# Format one child for insertion under a task line: 4-space indent; a bullet is kept as
# written, anything else becomes a '- ' bullet.
function Format-Child([string]$Child) {
    Assert-OneLine 'Children' $Child
    if ($Child -match '^\s') { return "    $Child" }
    if ($Child -match '^[-*+] ') { return "    $Child" }
    return "    - $Child"
}

# ---------------------------------------------------------------------------
# Repo, file, and line helpers
# ---------------------------------------------------------------------------

$VaultRoot = if ($VaultRootOverride) { Format-VaultRoot $VaultRootOverride } else { Get-VaultRoot -StartPath $PSScriptRoot }

# Resolve -Path (absolute or repo-relative, either separator) to an existing absolute path.
function Resolve-InputPath([string]$P) {
    $sep  = [string][System.IO.Path]::DirectorySeparatorChar
    $norm = $P -replace '[\\/]', $sep
    $abs  = Resolve-VaultPath -VaultRoot $VaultRoot -Path $norm
    if (-not (Test-Path -LiteralPath $abs)) { Fail "Path not found: $P" }
    return (Resolve-Path -LiteralPath $abs).Path
}

# Task files in the -Path scope (a file is taken as given), sorted by path.
function Get-ScopeFiles([string]$P) {
    if (-not $P) { return [string[]]@(Get-TaskFiles -VaultRoot $VaultRoot) }
    $abs = Resolve-InputPath $P
    if (Test-Path -LiteralPath $abs -PathType Leaf) { return [string[]]@($abs) }
    return [string[]]@(Get-TaskFiles -VaultRoot $VaultRoot -Path $abs)
}

function Get-Model([string]$File) { return Get-TaskFile -Path $File -VaultRoot $VaultRoot }

function Test-Blank([string]$Line) { return $Line.Trim() -eq '' }

# Index of the first '##' heading whose canonical section is $Name, skipping frontmatter and
# fenced blocks the way Get-TaskFile does; -1 when absent.
function Find-SectionIndex($Lines, [string]$Name) {
    $start = 0
    if ($Lines.Count -gt 0 -and $Lines[0].Trim() -eq '---') {
        for ($j = 1; $j -lt $Lines.Count; $j++) { if ($Lines[$j].Trim() -eq '---') { $start = $j + 1; break } }
    }
    $inFence = $false
    for ($i = $start; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        if ($Lines[$i] -match '^##(?!#)\s*(.*?)\s*$') {
            if ((Get-TaskSectionName $Matches[1]).Name -eq $Name) { return $i }
        }
    }
    return -1
}

# Whether items in $SectionName are separated by blank lines: the first adjacent pair of
# task blocks in that section decides, then the first pair anywhere in the file, else $true.
function Test-BlankSeparated($Model, [string]$SectionName) {
    foreach ($scope in @($SectionName, $null)) {
        $ts = @($Model.Tasks)
        for ($i = 0; $i -lt $ts.Count - 1; $i++) {
            $a = $ts[$i]; $b = $ts[$i + 1]
            if ($a.Section -ne $b.Section) { continue }
            if ($scope -and $a.Section -ne $scope) { continue }
            return ($b.LineNumber -gt $a.EndLine + 1)
        }
    }
    return $true
}

# Insert $Block as the first item under the heading at $HeadingIndex: after the heading's
# blank line (created if missing), then one blank line before a following heading, or before
# a following item when the section is blank-separated. Returns the block's first index.
function Add-Block([System.Collections.Generic.List[string]]$Lines, [int]$HeadingIndex, [string[]]$Block, [bool]$Separated) {
    $p = $HeadingIndex + 1
    if ($p -ge $Lines.Count -or -not (Test-Blank $Lines[$p])) { $Lines.Insert($p, '') }
    $at = $p + 1
    $Lines.InsertRange($at, $Block)
    $after = $at + $Block.Count
    if ($after -lt $Lines.Count) {
        $next = $Lines[$after]
        if ($next -match '^#') { $Lines.Insert($after, '') }
        elseif (-not (Test-Blank $next) -and $Separated) { $Lines.Insert($after, '') }
    }
    return $at
}

# Remove $Count lines at $Index, then drop one blank if that left two blanks in a row (or a
# blank as the file's last line).
function Remove-Block([System.Collections.Generic.List[string]]$Lines, [int]$Index, [int]$Count) {
    $Lines.RemoveRange($Index, $Count)
    if ($Index -gt 0 -and (Test-Blank $Lines[$Index - 1])) {
        if ($Index -lt $Lines.Count -and (Test-Blank $Lines[$Index])) { $Lines.RemoveAt($Index) }
        elseif ($Index -eq $Lines.Count) { $Lines.RemoveAt($Index - 1) }
    }
}

function New-LineList($Model) {
    $l = [System.Collections.Generic.List[string]]::new()
    foreach ($x in $Model.Lines) { $l.Add($x) }
    return , $l
}

function Save-Lines($Model, [System.Collections.Generic.List[string]]$Lines) {
    Set-FileLines -Path $Model.Path -Lines ([string[]]$Lines.ToArray()) -LineEnding $Model.LineEnding
}

# Mutable copy of a parsed task, in the shape ConvertTo-TaskLine reads.
function Copy-TaskFields($T) {
    return @{
        Symbol = $T.Symbol; Title = $T.Title; Text = $T.Text
        Tags = [System.Collections.Generic.List[string]]@($T.Tags)
        Priority = $T.Priority; Start = $T.Start; Scheduled = $T.Scheduled; Due = $T.Due
        Id = $T.Id; Created = $T.Created; DoneDate = $T.DoneDate; CancelledDate = $T.CancelledDate
        Extra = [string[]]@($T.Extra)
    }
}

# The contract's task object.
function ConvertTo-TaskOutput($T) {
    return [PSCustomObject][ordered]@{
        Id            = $T.Id
        IdNumber      = $T.IdNumber
        File          = $T.File
        LineNumber    = $T.LineNumber
        Section       = $T.Section
        Status        = $T.Status
        Symbol        = $T.Symbol
        Title         = $T.Title
        Text          = $T.Text
        Tags          = [string[]]@($T.Tags)
        Link          = $T.Link
        Promoted      = $T.Promoted
        Priority      = $T.Priority
        Start         = $T.Start
        Scheduled     = $T.Scheduled
        Due           = $T.Due
        Created       = $T.Created
        DoneDate      = $T.DoneDate
        CancelledDate = $T.CancelledDate
        Extra         = [string[]]@($T.Extra)
        Children      = [string[]]@($T.Children)
        Raw           = $T.Raw
    }
}

# Reload a file and return the output object of the task on 1-based line $LineNumber.
function Get-TaskAt([string]$File, [int]$LineNumber) {
    $m = Get-Model $File
    $t = @($m.Tasks | Where-Object { $_.LineNumber -eq $LineNumber })
    if ($t.Count -ne 1) { Fail "Internal error: no task on line $LineNumber of $($m.File) after the edit" }
    return ConvertTo-TaskOutput $t[0]
}

# Locate a task by numeric ID across every Tasks.md in the repo (Archive excluded).
function Find-Task([int]$TaskId) {
    $hits = [System.Collections.Generic.List[object]]::new()
    foreach ($f in Get-TaskFiles -VaultRoot $VaultRoot) {
        $m = Get-Model $f
        foreach ($t in $m.Tasks) { if ($t.IdNumber -eq $TaskId) { $hits.Add([PSCustomObject]@{ Model = $m; Task = $t }) } }
    }
    if ($hits.Count -eq 0) { Fail "Task $TaskId not found" }
    if ($hits.Count -gt 1) {
        $where = ($hits | ForEach-Object { "$($_.Task.File):$($_.Task.LineNumber)" }) -join ', '
        Fail "Task $TaskId is on more than one line ($where); fix the duplicate ID first"
    }
    return $hits[0]
}

# Every Task-*.md outside excluded folders (Archive included in the exclusion unless
# -IncludeArchive, which walks Archive folders too for closed tasks' archived docs).
function Get-TaskDocs([switch]$IncludeArchive) {
    $ex = @($TaskScanExcludedFolders)
    if ($IncludeArchive) { $ex = @($ex | Where-Object { $_ -ne 'Archive' }) }
    return [string[]]@(Get-PrunedFiles -Root $VaultRoot -Filter 'Task-*.md' -ExcludeFolderNames $ex)
}

function Find-TaskDoc([string]$Link) {
    foreach ($d in Get-TaskDocs) {
        if ([System.IO.Path]::GetFileNameWithoutExtension($d) -ieq $Link) { return $d }
    }
    return $null
}

function Write-Json($Value) {
    Write-Output (ConvertTo-Json -InputObject $Value -Depth 6)
}

# ---------------------------------------------------------------------------
# Verbs
# ---------------------------------------------------------------------------

function Invoke-List {
    $secs  = @(foreach ($x in @($Section)) { if ($x) { Get-SectionKey $x } })
    $stats = @(foreach ($x in @($Status)) { if ($x) { Get-StatusKey $x } })
    $tagsW = @(foreach ($x in @($Tag)) { if ($x) { $x.Trim().TrimStart('#') } })
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($f in Get-ScopeFiles $Path) {
        foreach ($t in (Get-Model $f).Tasks) {
            if ($secs.Count -and $secs -notcontains $t.Section) { continue }
            if ($stats.Count -and $stats -notcontains $t.Status) { continue }
            if ($script:Bound.ContainsKey('Id') -and ($null -eq $t.IdNumber -or $IdList -notcontains $t.IdNumber)) { continue }
            if ($tagsW.Count) {
                $hit = $false
                foreach ($w in $tagsW) { foreach ($x in $t.Tags) { if ($x -ieq $w) { $hit = $true } } }
                if (-not $hit) { continue }
            }
            $out.Add((ConvertTo-TaskOutput $t))
        }
    }
    Write-Json @($out.ToArray())
}

function Invoke-Check {
    $scopeFiles = Get-ScopeFiles $Path
    $allFiles   = [string[]]@(Get-TaskFiles -VaultRoot $VaultRoot)
    $models = @{}
    foreach ($f in @($allFiles) + @($scopeFiles)) { if (-not $models.ContainsKey($f)) { $models[$f] = Get-Model $f } }

    # IDs across the repo, for DuplicateId and OrphanDoc.
    $byId = @{}
    $idNumbers = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($f in $allFiles) {
        foreach ($t in $models[$f].Tasks) {
            if ($t.Id) {
                if (-not $byId.ContainsKey($t.Id)) { $byId[$t.Id] = [System.Collections.Generic.List[object]]::new() }
                $byId[$t.Id].Add($t)
            }
            if ($null -ne $t.IdNumber) { [void]$idNumbers.Add($t.IdNumber) }
        }
    }
    $docs = Get-TaskDocs
    $docNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($d in $docs) { [void]$docNames.Add([System.IO.Path]::GetFileNameWithoutExtension($d)) }
    # Closed tasks resolve their doc against a scan that includes Archive folders: marking a
    # promoted task done hands its doc to vault-doc-archive, which moves it into the context's
    # Archive/, so an archived doc is the expected home for a done or cancelled line's link,
    # not a missing one. OrphanDoc keeps using $docs (Archive excluded): an archived doc with
    # no line is pruned history, not a problem.
    $closedDocNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($d in Get-TaskDocs -IncludeArchive) { [void]$closedDocNames.Add([System.IO.Path]::GetFileNameWithoutExtension($d)) }

    $out = [System.Collections.Generic.List[object]]::new()
    function Add-Problem($File, $Line, [string]$Code, [string]$Message) {
        $out.Add([PSCustomObject][ordered]@{ File = $File; LineNumber = $Line; Code = $Code; Message = $Message })
    }

    foreach ($f in $scopeFiles) {
        $m = $models[$f]
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($p in $m.Problems) {
            $code = switch -Regex ($p.Message) {
                '^Unknown section'          { 'UnknownSection' }
                'uses the legacy name'      { 'LegacyHeading' }
                'empty title'               { 'EmptyTitle' }
                'in the Reminders section'  { 'CheckboxInReminders' }
                default                     { 'Unparsed' }
            }
            $items.Add([PSCustomObject]@{ Line = $p.LineNumber; Order = 0; Code = $code; Message = $p.Message })
        }
        foreach ($t in $m.Tasks) {
            if (-not $t.Id) { $items.Add([PSCustomObject]@{ Line = $t.LineNumber; Order = 1; Code = 'MissingId'; Message = 'Task line has no ID' }) }
            if (-not $t.Created) { $items.Add([PSCustomObject]@{ Line = $t.LineNumber; Order = 2; Code = 'MissingCreated'; Message = 'Task line has no created date' }) }
            if ($t.Section -ne 'Done' -and $t.Status -in 'done', 'cancelled') {
                $items.Add([PSCustomObject]@{ Line = $t.LineNumber; Order = 5; Code = 'DoneOutsideDone'; Message = "A $($t.Status) task is in section $($t.Section); only Done holds [x] and [-]" })
            }
            if ($t.Id -and $byId.ContainsKey($t.Id) -and $byId[$t.Id].Count -gt 1) {
                $others = ($byId[$t.Id] | Where-Object { -not ($_.File -eq $t.File -and $_.LineNumber -eq $t.LineNumber) } |
                    ForEach-Object { "$($_.File):$($_.LineNumber)" }) -join ', '
                $items.Add([PSCustomObject]@{ Line = $t.LineNumber; Order = 3; Code = 'DuplicateId'; Message = "ID $($t.Id) is also used at $others" })
            }
            $known = $docNames
            if ($t.Status -in 'done', 'cancelled') { $known = $closedDocNames }
            if ($t.Promoted -and $t.Link -match $TaskLink -and -not $known.Contains($t.Link)) {
                $items.Add([PSCustomObject]@{ Line = $t.LineNumber; Order = 4; Code = 'MissingDoc'; Message = "Linked task doc $($t.Link).md not found" })
            }
        }
        foreach ($it in ($items | Sort-Object Line, Order)) { Add-Problem $m.File $it.Line $it.Code $it.Message }
    }

    # Orphan docs under the scope folder (a file scope uses its folder).
    $scopeRoot = $null
    if ($Path) {
        $abs = Resolve-InputPath $Path
        $scopeRoot = if (Test-Path -LiteralPath $abs -PathType Leaf) { Split-Path $abs -Parent } else { $abs }
        $scopeRoot = Format-VaultRoot $scopeRoot
    }
    foreach ($d in $docs) {
        if ($scopeRoot -and -not $d.StartsWith($scopeRoot, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $name = [System.IO.Path]::GetFileName($d)
        if ($name -match '^Task-(\d+)(?:-.*)?\.md$') {
            $n = 0
            if ([int]::TryParse($Matches[1], [ref]$n) -and -not $idNumbers.Contains($n)) {
                $rel = _Get-RelPath $VaultRoot $d
                Add-Problem $rel $null 'OrphanDoc' "Task doc $name has no task line with ID $n"
            }
        }
    }
    Write-Json @($out.ToArray())
}

# Grouping tags (group/<name>) in the -Path scope, with the repo's View-*.md files naming
# each one. Tag and view matching ignore case; a group keeps the first spelling seen.
function Invoke-Groups {
    $cmp = [System.StringComparer]::OrdinalIgnoreCase
    $groups = [System.Collections.Generic.Dictionary[string, object]]::new($cmp)
    foreach ($f in Get-ScopeFiles $Path) {
        foreach ($t in (Get-Model $f).Tasks) {
            $seen = [System.Collections.Generic.HashSet[string]]::new($cmp)
            foreach ($tag in $t.Tags) {
                if ($tag -notmatch '^group/(.+)$') { continue }
                $name = $Matches[1]
                if (-not $seen.Add($name)) { continue }   # a tag repeated on one line counts once
                if (-not $groups.ContainsKey($name)) {
                    $groups[$name] = [PSCustomObject]@{ Name = $name; Open = 0; Closed = 0; Files = [System.Collections.Generic.HashSet[string]]::new($cmp) }
                }
                $g = $groups[$name]
                if ($t.Status -in 'todo', 'in-progress') { $g.Open++ }
                elseif ($t.Status -in 'done', 'cancelled') { $g.Closed++ }
                [void]$g.Files.Add($t.File)
            }
        }
    }
    if ($groups.Count -eq 0) { Write-Json @(); return }

    # View files repo-wide (never scoped by -Path), read once.
    $views = foreach ($v in Get-PrunedFiles -Root $VaultRoot -Filter 'View-*.md' -ExcludeFolderNames $TaskScanExcludedFolders) {
        $leaf = [System.IO.Path]::GetFileName($v)
        if ($leaf -notlike 'View-*.md') { continue }
        [PSCustomObject]@{ Rel = (_Get-RelPath $VaultRoot $v); Text = [System.IO.File]::ReadAllText($v, $Utf8NoBom) }
    }

    $names = [string[]]@($groups.Keys)
    [Array]::Sort($names, $cmp)
    $out = foreach ($n in $names) {
        $g = $groups[$n]
        $re = [regex]::new('#group/' + [regex]::Escape($g.Name) + '(?![\w/-])', 'IgnoreCase')
        $files = [string[]]@($g.Files)
        [Array]::Sort($files, $cmp)
        $hits = [string[]]@(foreach ($v in @($views)) { if ($re.IsMatch($v.Text)) { $v.Rel } })
        [Array]::Sort($hits, $cmp)
        [PSCustomObject][ordered]@{ Group = $g.Name; Open = $g.Open; Closed = $g.Closed; Files = $files; Views = $hits }
    }
    Write-Json @($out)
}

function Invoke-Add {
    if (-not $Path) { Fail '-Action add requires -Path' }
    if (-not $Title -or -not $Title.Trim()) { Fail '-Action add requires -Title' }
    Assert-OneLine 'Title' $Title
    $abs = Resolve-InputPath $Path
    if (Test-Path -LiteralPath $abs -PathType Container) {
        $abs = Join-Path $abs 'Tasks.md'
        if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { Fail "Tasks.md not found: $abs" }
    }
    $sec = if ($Section) { if (@($Section).Count -ne 1) { Fail '-Action add takes one -Section' }; Get-SectionKey $Section[0] } else { 'Backlog' }
    if ($sec -eq 'Done') { Fail 'Use -Action done or -Action cancel to put a task in Done; add takes Current, Blocked, Backlog, SideQuests, or Reminders' }

    $m = Get-Model $abs
    $h = Find-SectionIndex $m.Lines $sec
    if ($h -lt 0) { Fail "Section '$sec' not found in $($m.File)" }
    $lines = New-LineList $m

    if ($sec -eq 'Reminders') {
        foreach ($p in 'Text', 'Tags', 'Priority', 'Start', 'Scheduled', 'Due', 'Children', 'Status') {
            if ($script:Bound.ContainsKey($p)) { Fail "-$p does not apply to a reminder; reminders take only -Title" }
        }
        $at = Add-Block $lines $h @("- $($Title.Trim())") $false
        Save-Lines $m $lines
        $r = @((Get-Model $abs).Reminders | Where-Object { $_.LineNumber -eq $at + 1 })
        Write-Json ([PSCustomObject][ordered]@{ File = $m.File; LineNumber = $at + 1; Text = if ($r.Count) { $r[0].Text } else { $Title.Trim() } })
        return
    }

    $sym = ' '
    if ($Status) {
        if (@($Status).Count -ne 1) { Fail '-Action add takes one -Status' }
        $st = Get-StatusKey $Status[0]
        if ($st -in 'done', 'cancelled') { Fail "Use -Action done or -Action cancel to finish a task; add takes -Status todo or in-progress" }
        if ($st -eq 'in-progress') { $sym = '/' }
    }
    if ($script:Bound.ContainsKey('Text')) { Assert-OneLine 'Text' $Text }
    $task = @{
        Symbol = $sym; Title = $Title.Trim(); Text = if ($Text) { $Text.Trim() } else { '' }
        Tags = @(if ($Tags) { $Tags | ForEach-Object { Get-TagValue $_ } })
        Priority = $null; Start = $null; Scheduled = $null; Due = $null
        Id = [string](Get-NextTaskId -VaultRoot $VaultRoot); Created = $Today
    }
    if ($Priority) { $pk = Get-PriorityKey $Priority; if ($pk -ne 'none') { $task.Priority = $pk } }
    foreach ($k in 'Start', 'Scheduled', 'Due') {
        if ($script:Bound.ContainsKey($k)) { $v = Get-DateValue $k (Get-Variable $k -ValueOnly); if ($v) { $task[$k] = $v } }
    }
    $block = @(ConvertTo-TaskLine -Task $task) + @(if ($Children) { $Children | ForEach-Object { Format-Child $_ } })
    $at = Add-Block $lines $h ([string[]]$block) (Test-BlankSeparated $m $sec)
    Save-Lines $m $lines
    Write-Json (Get-TaskAt $abs ($at + 1))
}

function Invoke-Update {
    $tid = Get-SingleId
    $changes = 'Title', 'Text', 'AddTag', 'RemoveTag', 'Priority', 'Start', 'Scheduled', 'Due', 'Status', 'Section', 'AddChild'
    if (-not @($changes | Where-Object { $script:Bound.ContainsKey($_) }).Count) {
        Fail "-Action update needs at least one of: -$($changes -join ', -')"
    }
    $hit = Find-Task $tid
    $m = $hit.Model; $t = $hit.Task
    $f = Copy-TaskFields $t
    Add-MissingStamps $f

    if ($script:Bound.ContainsKey('Title')) {
        if (-not $Title.Trim()) { Fail '-Title cannot be empty' }
        Assert-OneLine 'Title' $Title
        $f.Title = $Title.Trim()
    }
    if ($script:Bound.ContainsKey('Text')) { Assert-OneLine 'Text' $Text; $f.Text = $Text.Trim() }
    foreach ($a in @($AddTag)) {
        if (-not $a) { continue }
        $v = Get-TagValue $a
        if (-not @($f.Tags | Where-Object { $_ -ieq $v }).Count) { $f.Tags.Add($v) }
    }
    foreach ($r in @($RemoveTag)) {
        if (-not $r) { continue }
        $v = $r.Trim().TrimStart('#')
        $f.Tags = [System.Collections.Generic.List[string]]@($f.Tags | Where-Object { $_ -ine $v })
    }
    if ($script:Bound.ContainsKey('Priority')) { $pk = Get-PriorityKey $Priority; $f.Priority = if ($pk -eq 'none') { $null } else { $pk } }
    foreach ($k in 'Start', 'Scheduled', 'Due') {
        if ($script:Bound.ContainsKey($k)) { $v = Get-DateValue $k (Get-Variable $k -ValueOnly); $f[$k] = if ($v) { $v } else { $null } }
    }
    if ($script:Bound.ContainsKey('Status')) {
        if (@($Status).Count -ne 1) { Fail '-Action update takes one -Status' }
        $st = Get-StatusKey $Status[0]
        if ($st -in 'done', 'cancelled') { Fail "Use -Action done or -Action cancel to set status $st" }
        $f.Symbol = if ($st -eq 'in-progress') { '/' } else { ' ' }
        $f.DoneDate = $null; $f.CancelledDate = $null
    }
    $target = $null
    if ($script:Bound.ContainsKey('Section')) {
        if (@($Section).Count -ne 1) { Fail '-Action update takes one -Section' }
        $target = Get-SectionKey $Section[0]
        if ($target -eq 'Done') { Fail 'Use -Action done or -Action cancel to move a task to Done' }
        if ($target -eq 'Reminders') { Fail 'A task cannot move to Reminders' }
        if ((Find-SectionIndex $m.Lines $target) -lt 0) { Fail "Section '$target' not found in $($m.File)" }
        if ($t.Status -in 'done', 'cancelled' -and -not $script:Bound.ContainsKey('Status')) {
            Fail "Task $tid is $($t.Status); pass -Status todo or in-progress to move it out of Done"
        }
    }

    $lines = New-LineList $m
    $idx = $t.LineNumber - 1
    $end = $t.EndLine - 1
    $lines[$idx] = ConvertTo-TaskLine -Task $f
    if ($AddChild) {
        $kids = [string[]]@($AddChild | ForEach-Object { Format-Child $_ })
        $lines.InsertRange($end + 1, $kids)
        $end += $kids.Count
    }
    $final = $idx
    if ($target) {
        $block = [string[]]$lines.GetRange($idx, $end - $idx + 1).ToArray()
        Remove-Block $lines $idx $block.Count
        $h = Find-SectionIndex $lines $target
        $final = Add-Block $lines $h $block (Test-BlankSeparated $m $target)
    }
    Save-Lines $m $lines
    Write-Json (Get-TaskAt $m.Path ($final + 1))
}

function Invoke-Finish([string]$Kind) {
    $tid = Get-SingleId
    $hit = Find-Task $tid
    $m = $hit.Model; $t = $hit.Task
    if ($t.Status -in 'done', 'cancelled') { Fail "Task $tid is already $($t.Status)" }
    if ((Find-SectionIndex $m.Lines 'Done') -lt 0) { Fail "Section 'Done' not found in $($m.File)" }

    $f = Copy-TaskFields $t
    Add-MissingStamps $f
    # Finishing is a plain move: title, text, tags, priority, and dates all stay on the line, so
    # a closed task keeps its context and its group tag (views and group counts still see it).
    $when = $Today
    if ($script:Bound.ContainsKey('Date')) {
        if ($Date -ieq 'none') { Fail "Invalid -Date 'none'. A finished task needs a date; omit -Date for today" }
        $when = Get-DateValue 'Date' $Date
        if ($when -gt $Today) { Fail "Invalid -Date '$Date'. It is after today ($Today)" }
    }
    if ($Kind -eq 'done') { $f.Symbol = 'x'; $f.DoneDate = $when; $f.CancelledDate = $null }
    else                  { $f.Symbol = '-'; $f.CancelledDate = $when; $f.DoneDate = $null }

    $lines = New-LineList $m
    $idx = $t.LineNumber - 1
    $block = [string[]](@(ConvertTo-TaskLine -Task $f) + @($t.Children))
    Remove-Block $lines $idx ($t.EndLine - $t.LineNumber + 1)
    $h = Find-SectionIndex $lines 'Done'
    $at = Add-Block $lines $h $block (Test-BlankSeparated $m 'Done')
    Save-Lines $m $lines

    $o = Get-TaskAt $m.Path ($at + 1)
    $linked = $null
    if ($t.Promoted -and $t.Link -match $TaskLink) { $linked = Find-TaskDoc $t.Link }
    $o | Add-Member -NotePropertyName LinkedDoc -NotePropertyValue $linked
    Write-Json $o
}

function Invoke-Promote {
    $tid = Get-SingleId
    $hit = Find-Task $tid
    $m = $hit.Model; $t = $hit.Task
    if ($t.Promoted) { Fail "Task $tid is already promoted: its title is the link $($t.Title)" }

    $docTitle = if ($script:Bound.ContainsKey('Title') -and $Title.Trim()) { Assert-OneLine 'Title' $Title; $Title.Trim() } else { $t.Title }
    $intro = if ($script:Bound.ContainsKey('Intro') -and $Intro.Trim()) { $Intro.Trim() } elseif ($t.Text) { $t.Text } else { $t.Title }
    if ($intro -notmatch '[.!?:]$') { $intro += '.' }
    $intro = ConvertTo-SentenceStart $intro
    $docTitle = ConvertTo-TitleCase $docTitle

    $docName = ConvertTo-TaskDocName -Id $tid -Title $docTitle
    $dir   = Split-Path $m.Path -Parent
    $inbox = Join-Path $dir 'Inbox'
    $docDir = if (Test-Path -LiteralPath $inbox -PathType Container) { $inbox } else { $dir }
    $docPath = Join-Path $docDir "$docName.md"
    if (Test-Path -LiteralPath $docPath) { Fail "Task doc already exists: $docPath" }

    $tasksLink = if ((Format-VaultRoot $dir) -ieq $VaultRoot) { 'Tasks' } else { "$(Split-Path $dir -Leaf)/Tasks" }
    $template = [System.IO.File]::ReadAllText((Join-Path $_skillDir 'templates' 'Task-Template.md'), $Utf8NoBom)
    $eol = if ($template.Contains("`r`n")) { "`r`n" } else { "`n" }
    $body = ''
    $kids = @($t.Children)
    if ($kids.Count) {
        $indents = @($kids | Where-Object { -not (Test-Blank $_) } | ForEach-Object { $_.Length - $_.TrimStart().Length })
        $min = ($indents | Measure-Object -Minimum).Minimum
        $ded = foreach ($c in $kids) { if (Test-Blank $c) { '' } else { $c.Substring([Math]::Min([int]$min, $c.Length)) } }
        $body = $eol + '## Notes' + $eol + $eol + (@($ded) -join $eol)
    }
    $doc = $template.Replace('{{Date}}', $Today).Replace('{{Title}}', $docTitle).Replace('{{TasksLink}}', $tasksLink).
        Replace('{{Intro}}', $intro).Replace('{{Body}}', $body)
    $doc = $doc.TrimEnd("`r", "`n") + $eol

    $f = Copy-TaskFields $t
    Add-MissingStamps $f
    $f.Title = "[[$docName]]"; $f.Text = ''
    $lines = New-LineList $m
    $idx = $t.LineNumber - 1
    $lines[$idx] = ConvertTo-TaskLine -Task $f
    if ($t.EndLine -gt $t.LineNumber) { Remove-Block $lines ($idx + 1) ($t.EndLine - $t.LineNumber) }

    [System.IO.File]::WriteAllText($docPath, $doc, $Utf8NoBom)
    Save-Lines $m $lines
    $o = Get-TaskAt $m.Path ($idx + 1)
    $o | Add-Member -NotePropertyName DocPath -NotePropertyValue $docPath
    Write-Json $o
}

function Invoke-Prune {
    if ($Days -lt 0) { Fail '-Days must be 0 or more' }
    $cutoff = (Get-Date).Date.AddDays(-$Days).ToString('yyyy-MM-dd')
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ScopeFiles $Path) {
        $m = Get-Model $file
        $pick = @($m.Tasks | Where-Object {
            $_.Section -eq 'Done' -and (
                ($_.DoneDate -and [string]::CompareOrdinal($_.DoneDate, $cutoff) -lt 0) -or
                ($_.CancelledDate -and [string]::CompareOrdinal($_.CancelledDate, $cutoff) -lt 0))
        })
        foreach ($t in $pick) { $selected.Add((ConvertTo-TaskOutput $t)) }
        if ($Apply -and $pick.Count) {
            $lines = New-LineList $m
            foreach ($t in ($pick | Sort-Object LineNumber -Descending)) {
                Remove-Block $lines ($t.LineNumber - 1) ($t.EndLine - $t.LineNumber + 1)
            }
            Save-Lines $m $lines
        }
    }
    Write-Json ([PSCustomObject][ordered]@{ Applied = [bool]$Apply; Tasks = @($selected.ToArray()) })
}

function Invoke-Backfill {
    $next = $null
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ScopeFiles $Path) {
        $m = Get-Model $file
        $lines = $null
        foreach ($t in $m.Tasks) {
            if ($t.Id -and $null -eq $t.IdNumber) { continue }   # non-numeric ID: left alone
            $needId = -not $t.Id
            $needCreated = -not $t.Created
            if (-not ($needId -or $needCreated)) { continue }
            $f = Copy-TaskFields $t
            if ($needId) {
                if ($null -eq $next) { $next = Get-NextTaskId -VaultRoot $VaultRoot }
                $f.Id = [string]$next; $next++
            }
            if ($needCreated) { $f.Created = $Today }
            if ($null -eq $lines) { $lines = New-LineList $m }
            $lines[$t.LineNumber - 1] = ConvertTo-TaskLine -Task $f
            $out.Add([PSCustomObject][ordered]@{ File = $m.File; LineNumber = $t.LineNumber; Id = $f.Id; StampedId = $needId; StampedCreated = $needCreated })
        }
        if ($null -ne $lines) { Save-Lines $m $lines }
    }
    Write-Json @($out.ToArray())
}

# Task lines in $Rel (repo-relative, '/') as committed at -Against; none when the file is
# absent there. Read leniently, line by line, with no section rules.
function Get-RefTasks([string]$Rel) {
    $text = git -C $VaultRoot.TrimEnd('\', '/') show "${Against}:./$Rel" 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return @(foreach ($l in @($text)) { $t = ConvertFrom-TaskLine -Line $l; if ($t) { $t } })
}

# Move all but one occurrence of each duplicated numeric ID onto fresh IDs; see the header
# for the keeper rules. Occurrences carry Order (file order, then line) for the tie-break.
function Invoke-Renumber {
    $one = $null
    if ($script:Bound.ContainsKey('Id')) { $one = Get-SingleId }
    if ($Path -and $null -eq $one) { Fail '-Action renumber takes -Path only with -Id' }
    if ($Path -and $Against) { Fail '-Path and -Against do not combine; -Path chooses the occurrences to renumber itself' }
    if ($Against) {
        $null = git -C $VaultRoot.TrimEnd('\', '/') rev-parse --verify --quiet "$Against^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) { Fail "Cannot resolve -Against '$Against' to a commit" }
    }

    $models = @{}
    $byId = [System.Collections.Generic.Dictionary[string, object]]::new()
    $order = 0
    foreach ($f in Get-TaskFiles -VaultRoot $VaultRoot) {
        $m = Get-Model $f
        $models[$m.Path] = $m
        foreach ($t in $m.Tasks) {
            if ($null -eq $t.IdNumber) { continue }
            if ($null -ne $one -and $t.IdNumber -ne $one) { continue }
            if (-not $byId.ContainsKey($t.Id)) { $byId[$t.Id] = [System.Collections.Generic.List[object]]::new() }
            $byId[$t.Id].Add([PSCustomObject]@{ Task = $t; Model = $m; Order = $order++; Published = $false })
        }
    }
    if ($null -ne $one -and $byId.Count -eq 0) { Fail "Task $one not found" }

    $scopeAbs = $null; $scopeLeaf = $false
    if ($Path) {
        $scopeAbs = Resolve-InputPath $Path
        $scopeLeaf = Test-Path -LiteralPath $scopeAbs -PathType Leaf
        if (-not $scopeLeaf) { $scopeAbs = Format-VaultRoot $scopeAbs }
    }
    $refCache = @{}
    $loc = { param($o) "$($o.Task.File):$($o.Task.LineNumber)" }
    $created = { param($o) if ($o.Task.Created) { $o.Task.Created } else { '9999-99-99' } }   # undated sorts last

    $plan = [System.Collections.Generic.List[object]]::new()
    $keys = [string[]]@($byId.Keys | Sort-Object { $byId[$_][0].Task.IdNumber }, { $_ })
    foreach ($k in $keys) {
        $occ = @($byId[$k])
        if ($Path) {
            $under = @($occ | Where-Object {
                if ($scopeLeaf) { $_.Model.Path -ieq $scopeAbs } else { $_.Model.Path.StartsWith($scopeAbs, [System.StringComparison]::OrdinalIgnoreCase) }
            })
            if ($under.Count -eq 0) { Fail "Task $one has no line under $Path" }
            if ($under.Count -eq $occ.Count) { Fail "Every line of task $one is under $Path; at least one must keep the ID" }
            foreach ($o in $under) { $plan.Add([PSCustomObject]@{ Occ = $o; Reason = "Path: under -Path $Path" }) }
            continue
        }
        if ($occ.Count -lt 2) { continue }

        # Published: the file at -Against has a line with this ID. Several occurrences in one
        # file each need a line of their own title there, so one published line covers one.
        if ($Against) {
            foreach ($grp in ($occ | Group-Object { $_.Task.File })) {
                $rel = $grp.Name
                if (-not $refCache.ContainsKey($rel)) { $refCache[$rel] = Get-RefTasks $rel }
                $hits = [System.Collections.Generic.List[object]]@($refCache[$rel] | Where-Object { $_.Id -eq $k })
                if ($hits.Count -eq 0) { continue }
                if ($grp.Count -eq 1) { $grp.Group[0].Published = $true; continue }
                foreach ($o in $grp.Group) {
                    $h = @($hits | Where-Object { $_.Title -ceq $o.Task.Title })
                    if ($h.Count) { $o.Published = $true; [void]$hits.Remove($h[0]) }
                }
            }
        }
        $pub = @($occ | Where-Object Published)
        $split = $pub.Count -gt 0 -and $pub.Count -lt $occ.Count
        $pool = if ($split) { $pub } else { $occ }
        $keep = @($pool | Sort-Object { & $created $_ }, Order)[0]
        foreach ($o in ($occ | Sort-Object Order)) {
            if ([object]::ReferenceEquals($o, $keep)) { continue }
            $why = if ($split -and -not $o.Published) { "Published: $(& $loc $keep) is in $Against and this line is not" }
                elseif ([string]::CompareOrdinal((& $created $o), (& $created $keep)) -gt 0) { "Created: $(& $loc $keep) was created earlier ($($keep.Task.Created))" }
                else { "Order: $(& $loc $keep) has the same created date and comes first in path order" }
            $plan.Add([PSCustomObject]@{ Occ = $o; Reason = $why })
        }
    }
    if ($plan.Count -eq 0) { Write-Json @(); return }

    $docs = $null
    $next = Get-NextTaskId -VaultRoot $VaultRoot
    $edits = @{}
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $plan) {
        $t = $p.Occ.Task
        # A line linking its own Task-<old> doc; a plan link or another task's doc is not one.
        $doc = $null
        if ($t.Promoted -and $t.Link -match ('^Task-' + [regex]::Escape($t.Id) + '(?:-|$)')) {
            if ($null -eq $docs) { $docs = Get-TaskDocs -IncludeArchive }
            $found = @($docs | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) -ieq $t.Link })
            if ($found.Count) { $doc = $found[0] }
        }
        $skip = $SkipPromoted -and $null -ne $doc
        $new = $null; $rename = $null
        if (-not $skip) {
            $new = $next++
            $f = Copy-TaskFields $t
            $f.Id = [string]$new
            if ($doc) {
                $oldRel = _Get-RelPath $VaultRoot $doc
                $stem = [System.IO.Path]::GetFileNameWithoutExtension($doc)
                $newName = "Task-$new" + $stem.Substring("Task-$($t.Id)".Length) + '.md'
                $rename = [PSCustomObject][ordered]@{ OldPath = $oldRel; NewPath = $oldRel.Substring(0, $oldRel.LastIndexOf('/') + 1) + $newName }
            } elseif ($t.Promoted -and $t.Link -match $TaskLink) {
                # No doc to rename, so nothing would fix the link later: point it at the new ID.
                $f.Title = $f.Title -replace ('^(\[\[(?:[^\]|#]*/)?)Task-' + [regex]::Escape($t.Id) + '(?=[-|#\]])'), "`${1}Task-$new"
            }
            $mp = $p.Occ.Model.Path
            if (-not $edits.ContainsKey($mp)) { $edits[$mp] = New-LineList $p.Occ.Model }
            $edits[$mp][$t.LineNumber - 1] = ConvertTo-TaskLine -Task $f
        }
        $out.Add([PSCustomObject][ordered]@{
            OldId = $t.IdNumber; NewId = $new; File = $t.File; LineNumber = $t.LineNumber
            Reason = $p.Reason; DocRename = $rename; Skipped = $skip
        })
    }
    if ($Apply) { foreach ($mp in $edits.Keys) { Save-Lines $models[$mp] $edits[$mp] } }
    Write-Json @($out.ToArray())
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

try {
    switch ($Action) {
        'list'     { Invoke-List }
        'check'    { Invoke-Check }
        'groups'   { Invoke-Groups }
        'add'      { Invoke-Add }
        'update'   { Invoke-Update }
        'promote'  { Invoke-Promote }
        'done'     { Invoke-Finish 'done' }
        'cancel'   { Invoke-Finish 'cancel' }
        'prune'    { Invoke-Prune }
        'backfill' { Invoke-Backfill }
        'renumber' { Invoke-Renumber }
    }
} catch {
    Fail $_.Exception.Message
}
exit 0
