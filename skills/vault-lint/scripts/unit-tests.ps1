# Unit tests for the vault-lint scripts.
# Run: pwsh .claude/skills/vault-lint/scripts/unit-tests.ps1
#
# Each lint script is invoked as a child process with -PathOverride and -VaultRootOverride
# pointing at a temporary git worktree, so tests are hermetic and never touch the
# live vault. Exits non-zero if any assertion fails.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lint-common.ps1"

# Relative paths in script output use the OS separator ('\' on Windows, '/' on Linux), so
# expected strings are built with it rather than a literal backslash.
$s = [System.IO.Path]::DirectorySeparatorChar
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')

$vaultRoot = Get-VaultRoot $PSScriptRoot
$override  = '.lint-test-tmp'

$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName $override
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot

# Typographic source characters, by codepoint.
$enDash = [char]0x2013; $emDash = [char]0x2014; $hBar = [char]0x2015; $figDash = [char]0x2012
$ldq    = [char]0x201C; $rdq    = [char]0x201D; $lsq  = [char]0x2018; $rsq     = [char]0x2019
$ell    = [char]0x2026; $nbsp   = [char]0x00A0

# Invoke a lint script as a child process scoped to the worktree test folder.
function Invoke-Lint {
    param([string]$Script, [string[]]$ExtraArgs = @())
    $scriptPath = Join-Path $PSScriptRoot $Script
    $a = @('-NoProfile', '-File', $scriptPath, '-PathOverride', $override, '-VaultRootOverride', $worktreePath) + $ExtraArgs
    (& pwsh @a 2>&1 | Out-String)
}

try {
    # ---- fix-typographic-chars ------------------------------------------------
    Write-Host "`nfix-typographic-chars.ps1"
    Reset-TestFolder
    New-TestFile 'Dashes.md'  "a $enDash b $emDash c $hBar d $figDash e"
    New-TestFile 'Curly.md'   "$($ldq)hi$($rdq) $($lsq)yo$($rsq)"
    New-TestFile 'EllNbsp.md' "wait${ell}then${nbsp}go"
    New-TestFile 'Clean.md'   "plain ascii - no issues here"

    $out = Invoke-Lint 'fix-typographic-chars.ps1'
    Assert-That 'preview flags dashes (4)'       ($out -match 'Would update: Dashes\.md' -and $out -match 'dashes: 4') $out
    Assert-That 'preview flags curly quotes'     ($out -match 'curly doubles: 2' -and $out -match 'curly singles: 2') $out
    # Regression: ellipsis/nbsp-only files were masked by culture-sensitive compare.
    Assert-That 'preview flags ellipsis + nbsp'  ($out -match 'EllNbsp\.md' -and $out -match 'ellipses: 1' -and $out -match 'non-break spaces: 1') $out
    Assert-That 'preview ignores clean file'     ($out -notmatch 'Clean\.md') $out

    Invoke-Lint 'fix-typographic-chars.ps1' @('-Update') | Out-Null
    Assert-That 'apply converts dashes to hyphen' ((Get-TestFileContent 'Dashes.md') -eq 'a - b - c - d - e') (Get-TestFileContent 'Dashes.md')
    Assert-That 'apply converts ellipsis + nbsp'  ((Get-TestFileContent 'EllNbsp.md') -eq 'wait...then go') (Get-TestFileContent 'EllNbsp.md')
    Assert-That 'apply leaves clean file intact'  ((Get-TestFileContent 'Clean.md') -eq 'plain ascii - no issues here') (Get-TestFileContent 'Clean.md')
    Assert-That 'apply writes no BOM'             (Test-NoBom 'Dashes.md')

    # ---- fix-trailing-whitespace ----------------------------------------------
    Write-Host "`nfix-trailing-whitespace.ps1"
    Reset-TestFolder
    New-TestFile 'Trail.md' "alpha   `nbeta`t`ngamma`n"
    New-TestFile 'Tidy.md'  "no trailing ws`nhere`n"

    $out = Invoke-Lint 'fix-trailing-whitespace.ps1'
    Assert-That 'preview flags trailing ws (2 lines)' ($out -match 'Would update: Trail\.md \(2 line\(s\)\)') $out
    Assert-That 'preview ignores tidy file'           ($out -notmatch 'Tidy\.md') $out

    Invoke-Lint 'fix-trailing-whitespace.ps1' @('-Update') | Out-Null
    Assert-That 'apply strips trailing ws' ((Get-TestFileContent 'Trail.md') -eq "alpha`nbeta`ngamma`n") (Get-TestFileContent 'Trail.md')
    Assert-That 'apply writes no BOM'      (Test-NoBom 'Trail.md')

    # ---- check-broken-wikilinks -----------------------------------------------
    Write-Host "`ncheck-broken-wikilinks.ps1"
    Reset-TestFolder
    New-TestFile 'Target.md' 'I am a real note.'
    New-TestFile 'Good.md'   'Link to [[Target]], alias [[Target|Display]], anchor [[Target#Section]].'
    New-TestFile 'Embed.md'  'An embed: ![[diagram.png]] and ![[Target]].'

    $out = Invoke-Lint 'check-broken-wikilinks.ps1'
    Assert-That 'resolves plain/alias/anchor links' ($out -match 'No broken wiki-links found\.') $out
    Assert-That 'ignores image embed'               ($out -notmatch 'diagram') $out

    Reset-TestFolder
    New-TestFile 'Orphan.md' 'Points at [[Nonexistent-Zzz]] which does not exist.'
    $out = Invoke-Lint 'check-broken-wikilinks.ps1'
    Assert-That 'detects broken link' ($out -match 'Broken: \[\[Nonexistent-Zzz\]\]') $out

    # Ignore list suppresses known-broken targets (case-insensitive, comments stripped).
    # The Broken-Link convention relies on the alias form [[Broken-Link|Original]] resolving
    # its target to the ignored sentinel while the display name is preserved.
    Reset-TestFolder
    New-TestFile 'Orphan.md'  'Points at [[Nonexistent-Zzz]], [[Broken-Link|Deleted-Note]] and [[Still-Broken]].'
    $ignorePath = Join-Path $testRoot 'ignore.txt'
    Set-Content -Path $ignorePath -Value "# a comment`nnonexistent-zzz   # inline comment`nBroken-Link`n" -Encoding utf8
    $out = Invoke-Lint 'check-broken-wikilinks.ps1' @('-IgnoreFileOverride', $ignorePath)
    Assert-That 'ignore list suppresses listed target'   ($out -notmatch 'Nonexistent-Zzz') $out
    Assert-That 'Broken-Link sentinel suppresses alias'  ($out -notmatch 'Deleted-Note') $out
    Assert-That 'ignore list keeps unlisted broken link' ($out -match 'Broken: \[\[Still-Broken\]\]') $out
    Assert-That 'reports ignored count'                  ($out -match '2 ignored via known-broken list') $out

    # Path-scoped ignores: a target under [path:prefix] is suppressed only in files under
    # that prefix, not in files elsewhere in the vault.
    Reset-TestFolder
    $subA = Join-Path $testRoot 'SubA'
    $subB = Join-Path $testRoot 'SubB'
    New-Item -ItemType Directory -Path $subA -Force | Out-Null
    New-Item -ItemType Directory -Path $subB -Force | Out-Null
    Set-Content -Path (Join-Path $subA 'Note-A.md') -Value 'Link to [[Scoped-Target]].' -Encoding utf8
    Set-Content -Path (Join-Path $subB 'Note-B.md') -Value 'Link to [[Scoped-Target]].' -Encoding utf8
    $ignorePath = Join-Path $testRoot 'scoped-ignore.txt'
    Set-Content -Path $ignorePath -Value "[path:$override/SubA]`nScoped-Target`n" -Encoding utf8
    $out = Invoke-Lint 'check-broken-wikilinks.ps1' @('-IgnoreFileOverride', $ignorePath)
    Assert-That 'scoped ignore suppresses link in matching path'  ($out -notmatch 'Note-A') $out
    Assert-That 'scoped ignore keeps link visible in other path'  ($out -match 'Broken: \[\[Scoped-Target\]\]' -and $out -match 'Note-B') $out
    Assert-That 'scoped ignore reports ignored count'             ($out -match '1 ignored via known-broken list') $out

    # Frontmatter coverage: quoted, path-qualified [[...]] links in frontmatter are scanned
    # like body links (whole-file content match + path-suffix resolution). This is what lets
    # vault-agent-frontmatter's validate script leave wikilink resolution to this check.
    Reset-TestFolder
    New-TestFile 'Real-Target.md' 'I exist.'
    New-TestFile 'Fm-Good.md'   "---`nnav.contents:`n  - link: `"[[Real-Target]]`"`n    description: `"d`"`n---`n# Body`n"
    New-TestFile 'Fm-Broken.md' "---`nnav.contents:`n  - link: `"[[Corpus/Ghost-Note]]`"`n    description: `"d`"`n---`n# Body`n"
    $out = Invoke-Lint 'check-broken-wikilinks.ps1'
    Assert-That 'resolves frontmatter link'       ($out -notmatch 'Real-Target') $out
    Assert-That 'detects broken frontmatter link' ($out -match 'Broken: \[\[Ghost-Note\]\]' -and $out -match 'Fm-Broken\.md') $out

    # ---- check-markdown-anchor-links --------------------------------------------
    Write-Host "`ncheck-markdown-anchor-links.ps1"
    Reset-TestFolder
    New-TestFile 'SamePage.md'        "# Title`n`n## My Section`n`nSee [My Section](#my-section) and [click here](#my-section)."
    New-TestFile 'CrossTarget.md'     "# Cross Target`n`n## Other Heading`n`nBody text."
    New-TestFile 'CrossSource.md'     "Link: [Other Heading](CrossTarget#other-heading)."
    New-TestFile 'NoHeadingMatch.md'  "# Title`n`n## Real Heading`n`nSee [Ghost](#ghost-heading)."
    New-TestFile 'AmbiguousHeading.md' "# Title`n`n## Foo Bar`n`n## foo bar`n`nSee [Foo](#foo-bar)."
    New-TestFile 'MissingTarget.md'   "See [Ghost](Nonexistent-File#anything)."
    New-TestFile 'ExternalLink.md'    "See [External](https://example.com/page#section) and [Mail](mailto:test@example.com#x)."
    New-TestFile 'SubA/Dup.md'        "## Heading One`n`nbody"
    New-TestFile 'SubB/Dup.md'        "## Heading One`n`nbody"
    New-TestFile 'AmbiguousTarget.md' "See [Heading One](Dup#heading-one)."
    New-TestFile 'BacktickExample.md' "See the pattern ``[Section Name](#section-name)`` in the guide."

    $out = Invoke-Lint 'check-markdown-anchor-links.ps1'
    Assert-That 'same-page bare match fixable'      ($out -match '\[My Section\]\(#my-section\)\s+->\s+\[\[#My Section\]\]') $out
    Assert-That 'same-page alias match fixable'     ($out -match '\[click here\]\(#my-section\)\s+->\s+\[\[#My Section\|click here\]\]') $out
    Assert-That 'cross-file match fixable'          ($out -match '\[Other Heading\]\(CrossTarget#other-heading\)\s+->\s+\[\[CrossTarget#Other Heading\]\]') $out
    Assert-That 'no heading match reported'         ($out -match "NoHeadingMatch\.md" -and $out -match "no heading matches '#ghost-heading'") $out
    Assert-That 'ambiguous heading reported'        ($out -match 'AmbiguousHeading\.md' -and $out -match 'ambiguous heading: 2 headings match') $out
    Assert-That 'missing target file reported'      ($out -match 'MissingTarget\.md' -and $out -match 'target file not found: Nonexistent-File') $out
    Assert-That 'ambiguous target file reported'    ($out -match 'AmbiguousTarget\.md' -and $out -match "ambiguous target: 2 files named 'Dup'") $out
    Assert-That 'external links never flagged'      ($out -notmatch 'ExternalLink') $out
    Assert-That 'backtick-quoted illustration never flagged' ($out -notmatch 'BacktickExample') $out

    Invoke-Lint 'check-markdown-anchor-links.ps1' @('-Update') | Out-Null
    Assert-That 'apply rewrites same-page links'  ((Get-TestFileContent 'SamePage.md').Contains('[[#My Section]]') -and (Get-TestFileContent 'SamePage.md').Contains('[[#My Section|click here]]')) (Get-TestFileContent 'SamePage.md')
    Assert-That 'apply rewrites cross-file link'  ((Get-TestFileContent 'CrossSource.md').Contains('[[CrossTarget#Other Heading]]')) (Get-TestFileContent 'CrossSource.md')
    Assert-That 'apply leaves unresolved link untouched' ((Get-TestFileContent 'NoHeadingMatch.md').Contains('[Ghost](#ghost-heading)')) (Get-TestFileContent 'NoHeadingMatch.md')
    Assert-That 'apply writes no BOM' (Test-NoBom 'SamePage.md')

    # ---- Get-VaultMarkdownFiles -IncludeHiddenFolders --------------------------
    Write-Host "`nGet-VaultMarkdownFiles -IncludeHiddenFolders"
    $hiddenRoot = Join-Path ([System.IO.Path]::GetTempPath()) "vault-hidden-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $hiddenRoot | Out-Null
    try {
        [System.IO.File]::WriteAllText((Join-Path $hiddenRoot 'Visible.md'), 'x', $Utf8NoBom)
        $hiddenDir = Join-Path $hiddenRoot '.hidden'
        New-Item -ItemType Directory -Path $hiddenDir | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $hiddenDir 'Secret.md'), 'x', $Utf8NoBom)

        $default = Get-VaultMarkdownFiles -VaultRoot (Format-VaultRoot $hiddenRoot)
        Assert-That 'default full scan skips dot-prefixed folder' (-not ($default | Where-Object { $_.Name -eq 'Secret.md' })) ($default | ForEach-Object { $_.Name })

        $withHidden = @(Get-VaultMarkdownFiles -VaultRoot (Format-VaultRoot $hiddenRoot) -IncludeHiddenFolders)
        Assert-That 'IncludeHiddenFolders switch includes dot-prefixed folder' (@($withHidden | Where-Object { $_.Name -eq 'Secret.md' }).Count -eq 1) ($withHidden | ForEach-Object { $_.Name })
        Assert-That 'IncludeHiddenFolders switch still includes visible file'  (@($withHidden | Where-Object { $_.Name -eq 'Visible.md' }).Count -eq 1) ($withHidden | ForEach-Object { $_.Name })
    } finally {
        Remove-Item -Recurse -Force $hiddenRoot -ErrorAction SilentlyContinue
    }

    # ---- check-filename-conventions -------------------------------------------
    Write-Host "`ncheck-filename-conventions.ps1"
    Reset-TestFolder
    New-TestFile 'Bad Name.md'     'x'
    New-TestFile 'Bad_Name.md'     'x'
    New-TestFile 'foo-Bar.md'      'x'
    New-TestFile 'Road-to-Hana.md' 'x'
    New-TestFile 'of-Mice.md'      'x'
    New-TestFile 'README.md'       'x'
    New-TestFile 'Good-Title.md'   'x'

    $out = Invoke-Lint 'check-filename-conventions.ps1'
    Assert-That 'flags spaces'               ($out -match 'Bad Name\.md' -and $out -match 'contains spaces') $out
    Assert-That 'flags underscores'          ($out -match 'Bad_Name\.md' -and $out -match 'contains underscores') $out
    Assert-That 'flags lowercase segment'    ($out -match 'foo-Bar\.md' -and $out -match 'not Title-Case') $out
    Assert-That 'allows minor word mid-name' ($out -notmatch 'Road-to-Hana\.md') $out
    Assert-That 'flags leading minor word'   ($out -match 'of-Mice\.md') $out
    Assert-That 'allows all-caps name'       ($out -notmatch 'README\.md') $out
    Assert-That 'allows clean Title-Case'    ($out -notmatch 'Good-Title\.md') $out

    # ---- check-provenance.ps1 ---------------------------------------------------
    Write-Host "`ncheck-provenance.ps1"

    # This check's recovery chains are git-history-dependent (Get-CreatedDate /
    # Get-ArchivedDate call `git log --follow`), so fixtures need real, dated commits
    # rather than the plain untracked files the other checks use. It also runs in
    # full-vault-scan mode (no -PathOverride) against a real root. A fresh, isolated repo - not the shared worktree above -
    # keeps this history and scan mode independent of the vault's own commit log.
    $provRoot = Join-Path ([System.IO.Path]::GetTempPath()) "vault-provenance-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $provRoot | Out-Null
    git -C $provRoot init -q 2>&1 | Out-Null
    git -C $provRoot config user.email test@test.com 2>&1 | Out-Null
    git -C $provRoot config user.name Test 2>&1 | Out-Null

    function New-ProvFile {
        param([string]$RelPath, [string]$Content = '')
        $abs = Join-Path $provRoot $RelPath
        $dir = Split-Path $abs -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [System.IO.File]::WriteAllText($abs, $Content, $Utf8NoBom)
    }
    function New-ProvCommit {
        param([string]$Date, [string]$Message = 'test commit')
        git -C $provRoot add -A 2>&1 | Out-Null
        $env:GIT_AUTHOR_DATE = "$Date 12:00:00"; $env:GIT_COMMITTER_DATE = "$Date 12:00:00"
        git -C $provRoot commit -q -m $Message 2>&1 | Out-Null
        Remove-Item Env:\GIT_AUTHOR_DATE, Env:\GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
    }
    function Move-ProvFile {
        param([string]$FromRelPath, [string]$ToRelPath, [string]$Date, [string]$Message = 'test move')
        $fromAbs = Join-Path $provRoot $FromRelPath
        $toAbs   = Join-Path $provRoot $ToRelPath
        $toDir   = Split-Path $toAbs -Parent
        if (-not (Test-Path $toDir)) { New-Item -ItemType Directory -Force -Path $toDir | Out-Null }
        git -C $provRoot mv $fromAbs $toAbs 2>&1 | Out-Null
        New-ProvCommit -Date $Date -Message $Message
    }
    function Invoke-Provenance {
        param([string[]]$ExtraArgs = @())
        $scriptPath = Join-Path $PSScriptRoot 'check-provenance.ps1'
        $a = @('-NoProfile', '-File', $scriptPath, '-VaultRootOverride', $provRoot) + $ExtraArgs
        (& pwsh @a 2>&1 | Out-String)
    }

    try {
        # A - both fields already present: no violation, no commit needed. Also carries
        # doc.type so it doesn't incidentally trip Check 3 (this fixture is Check 1's).
        New-ProvFile 'Archive/Both-Present.md' "---`ndoc.created: 2020-01-01`ndoc.archived: 2020-02-01`ndoc.type: Note`n---`n# Both`n"

        # B - created backfilled from a trailing filename date; archived already present.
        New-ProvFile 'Archive/Note-2020-03-05.md' "---`ndoc.archived: 2020-03-10`n---`n# Note`n"

        # C - created backfilled from git's first-add date (no filename date); archived
        # already present. Nested under Projects/Sample/Archive/ to prove the "any path
        # segment named Archive" match, not just a root-level Archive/.
        New-ProvFile 'Projects/Sample/Archive/Plain-Note.md' "---`ndoc.archived: 2020-04-20`n---`n# Plain`n"
        New-ProvCommit -Date '2020-04-15' -Message 'add Plain-Note'

        # D - archived backfilled from the Inbox -> Archive rename crossing; created
        # already present. Nested under Areas/Test/Archive/ for the same reason as C.
        New-ProvFile 'Areas/Test/Inbox/Cross-Note.md' "---`ndoc.created: 2020-05-01`n---`n# Cross`n"
        New-ProvCommit -Date '2020-05-01' -Message 'add Cross-Note'
        Move-ProvFile 'Areas/Test/Inbox/Cross-Note.md' 'Areas/Test/Archive/Cross-Note.md' -Date '2020-05-10' -Message 'archive Cross-Note'

        # E - regression: a file later rolled up by compact-archive.ps1's month
        # compaction changes path again after the true archive date. Recovery must
        # return the crossing date (2020-06-05), not the compaction date (2020-07-01).
        New-ProvFile 'Areas/Test/Inbox/Compact-Note.md' "---`ndoc.created: 2020-06-01`n---`n# Compact`n"
        New-ProvCommit -Date '2020-06-01' -Message 'add Compact-Note'
        Move-ProvFile 'Areas/Test/Inbox/Compact-Note.md' 'Areas/Test/Archive/Compact-Note.md' -Date '2020-06-05' -Message 'archive Compact-Note'
        Move-ProvFile 'Areas/Test/Archive/Compact-Note.md' 'Areas/Test/Archive/2020-06/Compact-Note.md' -Date '2020-07-01' -Message 'compact Compact-Note'

        # F - added directly at its Archive path, never renamed (the plan's motivating
        # bypass case): created recovers from the add commit; archived has no crossing to
        # recover from and is correctly left for manual resolution.
        New-ProvFile 'Archive/Direct-Add.md' "# Direct`n"
        New-ProvCommit -Date '2020-08-12' -Message 'add Direct-Add directly in Archive'

        # P - Check 4 candidate: archived file with a stale use_skill: entry alongside a
        # bare hint and a pinned: entry, both of which must survive the strip. Also carries
        # both dates already so it doesn't incidentally trip Check 1.
        New-ProvFile 'Archive/Stale-Skill.md' "---`ndoc.created: 2020-01-01`ndoc.archived: 2020-02-01`ndoc.type: Note`nagent.instructions:`n  - `"Load X when Y`"`n  - pinned: `"Never exfil this`"`n  - use_skill: `"vault-docs`"`n    when: `"editing this file`"`n---`n# Stale`n"

        # Q - Check 4 negative: archived file whose agent.instructions has only bare/pinned
        # entries, no use_skill: - must not be flagged.
        New-ProvFile 'Archive/Clean-Skill.md' "---`ndoc.created: 2020-01-01`ndoc.archived: 2020-02-01`ndoc.type: Note`nagent.instructions:`n  - pinned: `"Never exfil this`"`n---`n# Clean`n"

        # R - Check 4 + Check 1 interaction: an archived file missing doc.created AND
        # carrying a stale use_skill: entry - both checks must fire and both writes must
        # land in the same apply pass without clobbering each other. Committed here (before
        # G's untracked fixture below) so this commit's `git add -A` cannot inadvertently
        # give G's file a recoverable git-add date.
        New-ProvFile 'Archive/Both-Stale.md' "---`ndoc.archived: 2020-02-01`ndoc.type: Note`nagent.instructions:`n  - use_skill: `"vault-docs`"`n    when: `"editing this file`"`n---`n# Both`n"
        New-ProvCommit -Date '2020-09-01' -Message 'add Both-Stale'

        # G - never committed at all: neither field is recoverable from anywhere.
        New-ProvFile 'Archive/Untracked-Note.md' "# Untracked`n"

        # H - vault-wide Check 2 candidate: missing doc.created:, not under Archive/.
        New-ProvFile 'Resources/Regular-Doc.md' "# Regular Doc`n"

        # I - folder note (basename == parent folder name): excluded from both checks.
        New-ProvFile 'SubDir/SubDir.md' "# SubDir`n"

        # J - Tasks.md: excluded by filename from both checks.
        New-ProvFile 'Tasks.md' "# Tasks`n"

        # K - top-level Tasks/ holds task views, which are content docs and are checked.
        New-ProvFile 'Tasks/View-Open.md' "# View Open`n"

        # L - vault-wide Check 3 candidate: missing doc.type, not a Guide doc.
        New-ProvFile 'Resources/No-Type-Doc.md' "# No Type Doc`n"

        # M - has doc.type already: not flagged by Check 3.
        New-ProvFile 'Resources/Has-Type-Doc.md' "---`ndoc.type: Note`n---`n# Has Type Doc`n"

        # N - Guide doc (under .claude/guides/): excluded from Check 3 even though
        # it's a real authored document for Checks 1/2.
        New-ProvFile '.claude/guides/Some-Guide.md' "# Some-Guide.md - A Guide`n"

        # T - Guide doc at the vault's own relocated guide set (Resources/Vault/Guides/):
        # excluded from Check 3 for the same reason as N.
        New-ProvFile 'Resources/Vault/Guides/Some-Guide.md' "# Some-Guide.md - A Guide`n"

        # O - pure Templater script (no markdown body at all): excluded from all three checks,
        # unlike an ordinary file under Templates/ (which stays in scope - it's a real doc).
        New-ProvFile 'Resources/Vault/Templates/Script-Only.md' "<%*`nconst x = 1;`n%>`n"

        # S - regression: a real template doc (like Meeting-Template.md) with a leading
        # Templater <%* ... %> block *before* its `---` frontmatter fence, and real doc.*
        # fields inside that fence. Get-FrontmatterLines requires content to start with
        # `---`, so it can't see this frontmatter at all and both fields would otherwise
        # read as missing - excluded from Checks 2/3 via Test-IsTemplateDoc instead.
        New-ProvFile 'Resources/Vault/Templates/Meeting-Template.md' "<%*`nconst x = 1;`n-%>`n---`ndoc.created: <% today %>`ndoc.type: Meeting`n---`n# Meeting`n"

        $out = Invoke-Provenance

        Assert-That 'A: both-present file is not flagged'         (-not $out.Contains('Both-Present')) $out
        Assert-That 'B: created backfilled from filename date'    ($out.Contains("Would repair: Archive${s}Note-2020-03-05.md (doc.created: 2020-03-05)")) $out
        Assert-That 'C: created backfilled from git added-date'   ($out.Contains("Would repair: Projects${s}Sample${s}Archive${s}Plain-Note.md (doc.created: 2020-04-15)")) $out
        Assert-That 'D: archived backfilled from rename crossing' ($out.Contains("Would repair: Areas${s}Test${s}Archive${s}Cross-Note.md (doc.archived: 2020-05-10)")) $out
        Assert-That 'E: regression - archived is the crossing date, not the compaction date' `
            ($out.Contains("Would repair: Areas${s}Test${s}Archive${s}2020-06${s}Compact-Note.md (doc.archived: 2020-06-05)") -and -not $out.Contains('doc.archived: 2020-07-01')) $out
        Assert-That 'F: direct-add - created repaired, archived flagged manual' `
            ($out.Contains("Would repair: Archive${s}Direct-Add.md (doc.created: 2020-08-12)") -and $out.Contains("Manual resolution needed: Archive${s}Direct-Add.md (missing: doc.archived)")) $out
        Assert-That 'G: fully untracked file needs manual resolution for both fields' `
            ($out.Contains("Manual resolution needed: Archive${s}Untracked-Note.md (missing: doc.created, doc.archived)")) $out
        Assert-That 'H: non-archive file missing created flagged in Check 2' `
            ($out.Contains("Missing 'doc.created:': Resources${s}Regular-Doc.md")) $out
        Assert-That 'I: folder note excluded entirely'              (-not $out.Contains('SubDir')) $out
        Assert-That 'J: Tasks.md excluded entirely'                 (-not $out.Contains('Tasks.md')) $out
        Assert-That 'K: top-level Tasks/ task views are checked'     ($out.Contains("Missing 'doc.created:': Tasks${s}View-Open.md")) $out
        Assert-That 'Check 1 repairs are not double-reported by Check 2' `
            (-not $out.Contains("Missing 'doc.created:': Archive${s}Note-2020-03-05.md") -and
             -not $out.Contains("Missing 'doc.created:': Projects${s}Sample${s}Archive${s}Plain-Note.md")) $out
        Assert-That 'L: non-Guide file missing doc.type flagged in Check 3' `
            ($out.Contains("Missing 'doc.type:': Resources${s}No-Type-Doc.md")) $out
        Assert-That 'M: file with existing doc.type not flagged in Check 3' `
            (-not $out.Contains("Missing 'doc.type:': Resources${s}Has-Type-Doc.md")) $out
        Assert-That 'N: Guide doc excluded from Check 3' `
            (-not $out.Contains("Missing 'doc.type:': .claude${s}guides${s}Some-Guide.md")) $out
        Assert-That 'T: relocated Guide doc excluded from Check 3' `
            (-not $out.Contains("Missing 'doc.type:': Resources${s}Vault${s}Guides${s}Some-Guide.md")) $out
        Assert-That 'O: pure Templater script excluded from Check 2 and Check 3' `
            (-not $out.Contains('Script-Only.md')) $out
        Assert-That 'S: template doc with pre-frontmatter script block excluded from Check 2 and Check 3' `
            (-not $out.Contains('Meeting-Template.md')) $out
        Assert-That 'P: archived file with stale use_skill: flagged in Check 4' `
            ($out.Contains("Would strip: Archive${s}Stale-Skill.md")) $out
        Assert-That 'Q: archived file with only bare/pinned entries not flagged in Check 4' `
            (-not $out.Contains('Clean-Skill.md')) $out
        Assert-That 'R: archived file missing created and carrying stale use_skill: flagged in both Check 1 and Check 4' `
            ($out.Contains("Would repair: Archive${s}Both-Stale.md (doc.created: 2020-09-01)") -and $out.Contains("Would strip: Archive${s}Both-Stale.md")) $out

        # -Update actually writes the recovered values, preserves existing fields, writes
        # no BOM, and never touches Check 2's report-only candidates.
        Invoke-Provenance -ExtraArgs @('-Update') | Out-Null
        $noteContent = [System.IO.File]::ReadAllText((Join-Path $provRoot 'Archive/Note-2020-03-05.md'))
        Assert-That 'apply writes recovered created, keeps existing archived' `
            ($noteContent.Contains('doc.created: 2020-03-05') -and $noteContent.Contains('doc.archived: 2020-03-10')) $noteContent
        $directBytes = [System.IO.File]::ReadAllBytes((Join-Path $provRoot 'Archive/Direct-Add.md'))
        Assert-That 'apply writes no BOM' (-not ($directBytes.Length -ge 3 -and $directBytes[0] -eq 239 -and $directBytes[1] -eq 187 -and $directBytes[2] -eq 191))
        $regularContent = [System.IO.File]::ReadAllText((Join-Path $provRoot 'Resources/Regular-Doc.md'))
        Assert-That 'apply never writes Check 2 (report-only) candidates' (-not $regularContent.Contains('doc.created:')) $regularContent

        $staleContent = [System.IO.File]::ReadAllText((Join-Path $provRoot 'Archive/Stale-Skill.md'))
        Assert-That 'apply strips use_skill: entry, keeps bare and pinned entries' `
            ((-not $staleContent.Contains('use_skill')) -and $staleContent.Contains('Load X when Y') -and $staleContent.Contains('pinned: "Never exfil this"')) $staleContent
        $bothContent = [System.IO.File]::ReadAllText((Join-Path $provRoot 'Archive/Both-Stale.md'))
        Assert-That 'apply writes both Check 1 and Check 4 fixes to the same file without clobbering' `
            ($bothContent.Contains('doc.created: 2020-09-01') -and $bothContent.Contains('doc.archived: 2020-02-01') -and (-not $bothContent.Contains('use_skill'))) $bothContent
    } finally {
        Remove-Item -Recurse -Force $provRoot -ErrorAction SilentlyContinue
    }

    # ---- fix-hard-wrap.ps1 ------------------------------------------------------
    Write-Host "`nfix-hard-wrap.ps1"

    # Wrapped paragraph: plain prose safe-joins with a single space. The first line must be
    # near-full-width (>= $MinFullLineLength in the script) or the length gate will refuse to
    # fold the second line in - see the BoldLabelPairs/ShortLabelLongLine fixtures below for
    # the intentionally-short case this gate exists to catch.
    Reset-TestFolder
    New-TestFile 'Paragraph.md' "This is a wrapped paragraph that continues across quite a few words right here.`nIt keeps going on this second physical line before finally wrapping up."
    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/Paragraph.md")
    Assert-That 'wrapped paragraph auto-fixable'      ($out -match '\[auto-fixable\]') $out
    Assert-That 'wrapped paragraph joins with space'  ($out -match 'after:\s+This is a wrapped paragraph that continues across quite a few words right here\. It keeps going on this second physical line before finally wrapping up\.') $out

    # Length gate: two short adjacent bold-label lines (a definition-list shape) must NOT be
    # joined - the first line is well under $MinFullLineLength, so it's treated as an
    # intentional short line rather than a forced wrap break.
    Reset-TestFolder
    New-TestFile 'BoldLabelPairs.md' (@('**Item1:** blah', '**Item2:** blah') -join "`n")
    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/BoldLabelPairs.md")
    Assert-That 'adjacent short bold-label lines not joined' ($out -notmatch '\*\*Item1:\*\* blah \*\*Item2') $out

    # Length gate: a short bold name/label line immediately followed by one long, already-
    # unwrapped descriptive line (the real Meals.md shape) must NOT be joined either - the
    # label line is short, so it doesn't absorb the long line that follows it, and the long
    # line stands alone as a single-line block (no finding at all).
    Reset-TestFolder
    New-TestFile 'ShortLabelLongLine.md' (@(
        '**Nalu''s South Shore Grill** *(1280 S Kihei Rd - ~5 min walk)*'
        '4.7 stars | Local Hawaiian/American. Casual open-air. Known for poke bowls, ribs, creative breakfast. Good for all meals. No reservation needed. Open daily 8am-9pm. $$'
    ) -join "`n")
    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/ShortLabelLongLine.md")
    Assert-That 'short label not folded into long unwrapped line' ($out -notmatch 'walk\)\* 4\.7 stars') $out

    # Length gate does not overcorrect: a bold-prefixed line whose value is itself genuinely
    # long enough to have been hard-wrapped still joins with its continuation.
    Reset-TestFolder
    New-TestFile 'BoldLabelGenuineWrap.md' (@(
        '**Description:** This field holds a fairly long value that got hard-wrapped'
        'onto a second physical line by whatever tool originally authored this file.'
    ) -join "`n")
    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/BoldLabelGenuineWrap.md")
    Assert-That 'genuinely wrapped bold-prefixed value still joins' ($out -match 'after:\s+\*\*Description:\*\* This field holds a fairly long value that got hard-wrapped onto a second physical line by whatever tool originally authored this file\.') $out

    # Bold-label adjacency boundary: two independent `**Label:** value` lines must NOT be
    # joined even when the first line's value is long enough to have cleared the old length
    # gate on its own (the Project-Team.md/Vision.md/DAEC.md false-positive class) - the
    # incoming line matching the bold-label prefix always forces a new sub-block, regardless
    # of length.
    Reset-TestFolder
    New-TestFile 'BoldLabelLongValue.md' (@(
        '**Mike Dixon:** Previously with Duane Arnold in design engineering, helping with PPC piece'
        '**Erik Sorensen:** Responsible for implementation'
    ) -join "`n")
    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/BoldLabelLongValue.md")
    Assert-That 'long-value bold-label pair not joined' ($out -notmatch 'PPC piece \*\*Erik Sorensen') $out

    # Image-embed boundary: a numbered list item's instruction text must NOT absorb a
    # standalone screenshot embed on the next, continuation-indented line (the
    # Project-Document-Management.md false-positive class) - even though the indentation
    # matches the item's continuation column and the item's own line is full-width, a line
    # that is in its entirety a markdown image reference always forces a new sub-block.
    Reset-TestFolder
    New-TestFile 'ImageEmbedListItem.md' (@(
        '5. Navigate to the **Documents** folder and then the respective subfolder applicable for the current document.'
        '   ![image.png](/.attachments/image-aaa9a5eb-79dd-4bdf-8f0c-582e7f40c192.png)'
    ) -join "`n")
    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/ImageEmbedListItem.md")
    Assert-That 'image-embed line not folded into list item' ($out -notmatch 'document\. !\[image\.png\]') $out

    # List mechanics in one chunk (no blank lines, like a real list): a wrapped top-level item,
    # a parent item immediately followed by its own nested item (must NOT fold together even
    # though the nested marker's indentation coincidentally matches the parent's continuation
    # column), a nested item that itself wraps (safe to join), and a checklist item with an
    # aligned continuation indent.
    Reset-TestFolder
    $listArr = @(
        '- Wrapped top-level item that continues onward for quite a while right here'
        '  continues here with more descriptive text added to complete the thought.'
        '- Parent item wraps here with additional wording to make the line longer'
        '  - Nested item wraps here across the line with some extra padding words'
        '    across two lines to verify the joined nested continuation works fine.'
        '- Another parent that wraps here too with some extra padding text added now'
        '  - Nested item stays separate from its wrapping parent line naturally'
        '- [ ] Checklist item wraps here across the line with quite a bit of extra text'
        '      here at six spaces to complete the checklist item text nicely.'
    )
    New-TestFile 'List.md' ($listArr -join "`n")
    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/List.md")
    Assert-That 'top-level list item joins with space' ($out -match 'after:\s+- Wrapped top-level item that continues onward for quite a while right here continues here with more descriptive text added to complete the thought\.') $out
    Assert-That 'nested list item joins with space'    ($out -match 'after:\s+- Nested item wraps here across the line with some extra padding words across two lines to verify the joined nested continuation works fine\.') $out
    Assert-That 'checklist item joins with space'      ($out -match 'after:\s+- \[ \] Checklist item wraps here across the line with quite a bit of extra text here at six spaces to complete the checklist item text nicely\.') $out
    Assert-That 'own-marker nested item not folded into parent' ($out -notmatch 'Parent item wraps here.*continues|Another parent that wraps.*Nested item stays separate') $out

    $out = Invoke-Lint 'fix-hard-wrap.ps1'
    Assert-That 'preview reports 6 auto-fixable lines for List.md' ($out -match 'List\.md' -and $out -match 'auto-fixable: 6 line\(s\)') $out

    Invoke-Lint 'fix-hard-wrap.ps1' @('-Update') | Out-Null
    $expectedList = @(
        '- Wrapped top-level item that continues onward for quite a while right here continues here with more descriptive text added to complete the thought.'
        '- Parent item wraps here with additional wording to make the line longer'
        '  - Nested item wraps here across the line with some extra padding words across two lines to verify the joined nested continuation works fine.'
        '- Another parent that wraps here too with some extra padding text added now'
        '  - Nested item stays separate from its wrapping parent line naturally'
        '- [ ] Checklist item wraps here across the line with quite a bit of extra text here at six spaces to complete the checklist item text nicely.'
    ) -join "`n"
    Assert-That 'apply joins list blocks, leaves own-marker items untouched' ((Get-TestFileContent 'List.md') -eq $expectedList) (Get-TestFileContent 'List.md')
    Assert-That 'apply writes no BOM' (Test-NoBom 'List.md')

    # Structural exclusions: a plain fence exercises the same fence-toggle mechanism a mermaid
    # block would (the script doesn't special-case the fence language), so one fixture covers
    # both. Table row, blockquote/callout, and frontmatter each disqualify their whole chunk too.
    Reset-TestFolder
    New-TestFile 'Fence.md' (@('```', 'wrapped line one', 'wrapped line two', '```') -join "`n")
    New-TestFile 'Table.md' (@('| Col1 | Col2 |', '| --- | --- |', 'this line looks like it', 'continues to the next line') -join "`n")
    New-TestFile 'Quote.md' (@('> This is a quoted line', '> that wraps across two.') -join "`n")
    New-TestFile 'Frontmatter.md' (@('---', 'title: Something that', 'wraps across two lines', '---', '# Body') -join "`n")
    $out = Invoke-Lint 'fix-hard-wrap.ps1'
    Assert-That 'fenced code/mermaid block excluded' ($out -notmatch 'Fence\.md') $out
    Assert-That 'table excluded'                     ($out -notmatch 'Table\.md') $out
    Assert-That 'blockquote/callout excluded'         ($out -notmatch 'Quote\.md') $out
    Assert-That 'frontmatter excluded'                ($out -notmatch 'Frontmatter\.md') $out

    # Corruption safety: code-span and wikilink state tracked across the break point.
    Reset-TestFolder
    New-TestFile 'CodeBalanced.md'   (@('Here is a rather long and quite verbose introductory sentence that leads into a `code', 'span` that wraps.') -join "`n")
    New-TestFile 'CodeUnbalanced.md' (@('Here is a rather long and quite verbose introductory sentence that leads into a `code', 'span that continues.') -join "`n")
    New-TestFile 'LinkTarget.md'     (@('Please take a look at the following reference note before you continue reading: [[Vault-Guide', 'Overview]] here in this sentence.') -join "`n")
    New-TestFile 'LinkAlias.md'      (@('Please take a look at the following reference note before you continue reading: [[Vault-Guide|Guide', 'Text]] here in this sentence.') -join "`n")
    New-TestFile 'Embed.md'          (@('See the attached architecture diagram embed below for the full technical details right here: ![[diagram', 'one.png]] for details.') -join "`n")

    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/CodeBalanced.md")
    Assert-That 'balanced code span auto-fixable'     ($out -match '\[auto-fixable\]') $out
    Assert-That 'balanced code span joins with space' ($out -match 'after:\s+Here is a rather long and quite verbose introductory sentence that leads into a `code span` that wraps\.') $out

    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/CodeUnbalanced.md")
    Assert-That 'unbalanced code span flagged' ($out -match '\[flagged: unbalanced code span\]') $out

    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/LinkTarget.md")
    Assert-That 'note-link target break joins with no space' ($out -match 'after:\s+Please take a look at the following reference note before you continue reading: \[\[Vault-GuideOverview\]\] here in this sentence\.') $out

    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/LinkAlias.md")
    Assert-That 'note-link alias break joins with space' ($out -match 'after:\s+Please take a look at the following reference note before you continue reading: \[\[Vault-Guide\|Guide Text\]\] here in this sentence\.') $out

    $out = Invoke-Lint 'fix-hard-wrap.ps1' @('-InspectFile', "$override/Embed.md")
    Assert-That 'embed target break always flagged' ($out -match '\[flagged: break inside embed link\]') $out
    # ---- check-task-lines -----------------------------------------------------
    Write-Host "`ncheck-task-lines.ps1"
    Reset-TestFolder
    New-TestFile 'Areas/Demo/Tasks.md' (@(
        '# Demo Tasks', '',
        '## 🔔 Reminders', '', '- [ ] not a reminder', '',
        '## 🔥 Active', '', '- [ ] **No id yet**', '- [ ] [[Task-9001-Gone]] | 🆔 9001 ➕ 2026-10-17', '- [x] finished early | 🆔 9002 ➕ 2026-10-17 ✅ 2026-10-17', '',
        '## 🧱 Blocked', '', '## 📋 Backlog', '', '- [ ] | 🆔 9003 ➕ 2026-10-17', '',
        '## 🗺️ Side Quests', '', '## ✅ Done', '', '## Notes', ''
    ) -join "`n")
    New-TestFile 'Areas/Demo/Inbox/Task-9004-Orphan.md' "# Orphan`n"
    New-TestFile 'Areas/Legacy/Tasks.md' (@('# Legacy Tasks', '', '## 🔥 Sprint', '', '- [ ] old name | 🆔 9006 ➕ 2026-10-17', '', '## ✅ Done', '') -join "`n")
    New-TestFile 'Areas/Clean/Tasks.md' (@('# Clean Tasks', '', '## 🔥 Current', '', '- [ ] fine | 🆔 9005 ➕ 2026-10-17', '', '## ✅ Done', '') -join "`n")

    $out = Invoke-Lint 'check-task-lines.ps1'
    foreach ($code in 'LegacyHeading', 'CheckboxInReminders', 'MissingId', 'MissingCreated', 'EmptyTitle', 'MissingDoc', 'OrphanDoc', 'DoneOutsideDone', 'UnknownSection') {
        Assert-That "reports $code" ($out -match "$code \(\d+\):") $out
    }
    Assert-That 'names the file and line'    ($out -match 'Areas[\\/]Demo[\\/]Tasks\.md:9') $out
    Assert-That 'Sprint heading reported as legacy' ($out -match 'LegacyHeading \(2\):' -and $out -match 'Areas[\/]Legacy[\/]Tasks\.md:3 - .*legacy name Sprint; rename it to Current') $out
    Assert-That 'clean file not reported'    ($out -notmatch 'Clean[\\/]Tasks\.md') $out
    Assert-That 'totals the problems'        ($out -match '\d+ task line problem\(s\) found') $out

    $out = (& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'check-task-lines.ps1') -PathOverride "$override/Areas/Clean" -VaultRootOverride $worktreePath 2>&1 | Out-String)
    Assert-That 'scoped clean run reports none' ($out -match 'No task line problems found') $out
} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
