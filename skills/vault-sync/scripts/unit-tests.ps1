# unit-tests.ps1
# Test suite for vault-sync-git.ps1 (direct) and vault-sync.ps1 (via isolated temp repos).
# Pull/push scenarios use throwaway bare "remote" repos in the OS temp dir, never the
# vault's own worktree or remotes - Initialize-TestWorktree/Reset-TestFolder assume
# file-based worktree isolation against the vault repo, which doesn't apply here (same
# rationale as vault-credentials.unit-tests.ps1). Isolation instead comes from a
# uniquely-named temp base dir, removed in a finally block.
# Usage:  .\unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')
. (Join-Path $PSScriptRoot 'vault-sync-git.ps1')

$scriptPath = Join-Path $PSScriptRoot 'vault-sync.ps1'
$base = Join-Path ([System.IO.Path]::GetTempPath()) "vault-sync-test-$(Get-Random)"
New-Item -ItemType Directory -Path $base | Out-Null

# Local stand-in for Run-Test: reuses its pass/fail counters and output style, but skips
# Reset-TestFolder (see header note above).
function Run-Test {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    Write-Host "  $Name" -NoNewline
    try {
        $ok = & $Body
        if ($ok) {
            Write-Host '  PASS' -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host ''
            $script:failed++
        }
    } catch {
        Write-Host "`n  ERROR: $_" -ForegroundColor Red
        $script:failed++
    }
}

function Invoke-Sync {
    param([string[]]$ScriptArgs)
    $result = & pwsh -NonInteractive -NoProfile -File $scriptPath @ScriptArgs *>&1
    return @{
        Output = ($result | ForEach-Object { "$_" }) -join "`n"
        ExitCode = $LASTEXITCODE
    }
}

function New-GitRepo {
    param([string]$RepoPath, [switch]$Bare)
    New-Item -ItemType Directory -Force -Path $RepoPath | Out-Null
    if ($Bare) {
        git init -q --bare $RepoPath 2>&1 | Out-Null
    } else {
        git init -q $RepoPath 2>&1 | Out-Null
        git -C $RepoPath config user.email test@test.com 2>&1 | Out-Null
        git -C $RepoPath config user.name Test 2>&1 | Out-Null
        git -C $RepoPath config commit.gpgsign false 2>&1 | Out-Null
    }
}

function Write-RepoFile {
    param([string]$RepoPath, [string]$RelPath, [string]$Content)
    $abs = Join-Path $RepoPath $RelPath
    $dir = Split-Path $abs -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($abs, $Content, $Utf8NoBom)
}

function Add-CommitAll {
    param([string]$RepoPath, [string]$Message)
    git -C $RepoPath add -A 2>&1 | Out-Null
    git -C $RepoPath commit -q -m $Message 2>&1 | Out-Null
}

# Sets up a bare "remote" plus a "local" clone with one initial commit already pushed.
# Returns @{ Remote; Local }.
function New-RemoteAndLocal {
    param([string]$Name)
    $remote = Join-Path $base "$Name-remote.git"
    $local  = Join-Path $base "$Name-local"
    New-GitRepo -RepoPath $remote -Bare
    New-GitRepo -RepoPath $local
    git -C $local remote add origin $remote 2>&1 | Out-Null
    Write-RepoFile $local 'File.md' "initial`n"
    Add-CommitAll $local 'initial commit'
    git -C $local push -q -u origin master 2>&1 | Out-Null
    return @{ Remote = $remote; Local = $local }
}

try {

# ---------------------------------------------------------------------------
# Get-GitPullClassification (pure)
# ---------------------------------------------------------------------------

Write-Host "`n-- Get-GitPullClassification --"

Run-Test 'Exit 0, already up to date' {
    (Get-GitPullClassification -Output "Already up to date." -ExitCode 0) -eq 'UpToDate'
}

Run-Test 'Exit 0, fast-forward' {
    (Get-GitPullClassification -Output "Fast-forward`n Foo.md | 1 +" -ExitCode 0) -eq 'FastForward'
}

Run-Test 'Exit 0, real merge commit' {
    (Get-GitPullClassification -Output "Merge made by the 'ort' strategy." -ExitCode 0) -eq 'MergedClean'
}

Run-Test 'Exit 1, conflicted files supplied' {
    (Get-GitPullClassification -Output "Automatic merge failed" -ExitCode 1 -ConflictedFiles @('Foo.md')) -eq 'MergedConflicts'
}

Run-Test 'Exit 1, CONFLICT in output, no explicit file list' {
    (Get-GitPullClassification -Output "CONFLICT (content): Merge conflict in Foo.md" -ExitCode 1) -eq 'MergedConflicts'
}

Run-Test 'Exit 1, network failure text' {
    (Get-GitPullClassification -Output "fatal: unable to access 'https://example/': Could not resolve host: example" -ExitCode 1) -eq 'FailedNetwork'
}

Run-Test 'Exit 1, other failure' {
    (Get-GitPullClassification -Output "fatal: something unexpected" -ExitCode 1) -eq 'FailedOther'
}

# ---------------------------------------------------------------------------
# New-ConflictFilePath
# ---------------------------------------------------------------------------

Write-Host "`n-- New-ConflictFilePath --"

$fixedNow = [datetime]'2026-07-17 14:32:00'

Run-Test 'No directory' {
    (New-ConflictFilePath -RelPath 'Foo.md' -Now $fixedNow) -eq 'Foo [CONFLICT 20260717 1432].md'
}

Run-Test 'With directory, forward slashes preserved' {
    (New-ConflictFilePath -RelPath 'Areas/Foo/Bar.md' -Now $fixedNow) -eq 'Areas/Foo/Bar [CONFLICT 20260717 1432].md'
}

Run-Test 'Backslash directory normalized to forward slash' {
    (New-ConflictFilePath -RelPath 'Areas\Foo\Bar.md' -Now $fixedNow) -eq 'Areas/Foo/Bar [CONFLICT 20260717 1432].md'
}

# ---------------------------------------------------------------------------
# Test-GitDetachedHead / Test-GitMidMerge (real isolated repo, no vault worktree)
# ---------------------------------------------------------------------------

Write-Host "`n-- Test-GitDetachedHead / Test-GitMidMerge --"

$soloRepo = Join-Path $base 'solo'
New-GitRepo -RepoPath $soloRepo
Write-RepoFile $soloRepo 'File.md' "one`n"
Add-CommitAll $soloRepo 'first'
$firstSha = (git -C $soloRepo rev-parse HEAD).Trim()
Write-RepoFile $soloRepo 'File.md' "two`n"
Add-CommitAll $soloRepo 'second'

Run-Test 'Attached HEAD reports branch, not detached' {
    $r = Test-GitDetachedHead -RepoPath $soloRepo
    (-not $r.Detached) -and ($r.Branch -in @('master', 'main'))
}

Run-Test 'Detached HEAD reports Detached=true, Branch=null' {
    git -C $soloRepo checkout -q $firstSha 2>&1 | Out-Null
    $r = Test-GitDetachedHead -RepoPath $soloRepo
    $r.Detached -and (-not $r.Branch) -and ($r.HeadShort)
}

Run-Test 'No mid-merge on a clean repo' {
    git -C $soloRepo checkout -q master 2>&1 | Out-Null
    (Test-GitMidMerge -RepoPath $soloRepo).MidMerge -eq $false
}

# ---------------------------------------------------------------------------
# vault-sync.ps1 -Action Status / Reattach
# ---------------------------------------------------------------------------

Write-Host "`n-- Action: Status --"

$statusRepo = Join-Path $base 'status-repo'
New-GitRepo -RepoPath $statusRepo
Write-RepoFile $statusRepo 'File.md' "one`n"
Add-CommitAll $statusRepo 'first'

Run-Test 'Status reports attached branch and zero uncommitted' {
    $r = Invoke-Sync @('-Action', 'Status', '-VaultRootOverride', $base, '-Path', 'status-repo')
    (Assert-OutputContains $r.Output 'Detached: False') -and (Assert-OutputContains $r.Output 'UncommittedCount: 0')
}

Run-Test 'Status reports uncommitted change' {
    Write-RepoFile $statusRepo 'File.md' "modified`n"
    $r = Invoke-Sync @('-Action', 'Status', '-VaultRootOverride', $base, '-Path', 'status-repo')
    Assert-OutputContains $r.Output 'UncommittedCount: 1'
}

Add-CommitAll $statusRepo 'settle'

Write-Host "`n-- Action: Reattach --"

$firstShaStatus = (git -C $statusRepo rev-parse HEAD).Trim()
Write-RepoFile $statusRepo 'File.md' "branch-tip`n"
Add-CommitAll $statusRepo 'second'
git -C $statusRepo checkout -q $firstShaStatus 2>&1 | Out-Null

Run-Test 'Reattach checks out the branch from detached HEAD' {
    $r = Invoke-Sync @('-Action', 'Reattach', '-VaultRootOverride', $base, '-Path', 'status-repo', '-Branch', 'master')
    ($r.ExitCode -eq 0) -and (-not (Test-GitDetachedHead -RepoPath $statusRepo).Detached)
}

Run-Test 'Reattach refuses when uncommitted edit conflicts with target branch' {
    git -C $statusRepo checkout -q $firstShaStatus 2>&1 | Out-Null
    Write-RepoFile $statusRepo 'File.md' "uncommitted-conflicting-edit`n"
    $r = Invoke-Sync @('-Action', 'Reattach', '-VaultRootOverride', $base, '-Path', 'status-repo', '-Branch', 'master')
    git -C $statusRepo checkout -q -- 'File.md' 2>&1 | Out-Null
    git -C $statusRepo checkout -q master 2>&1 | Out-Null
    ($r.ExitCode -eq 1) -and (Assert-OutputContains $r.Output 'Reattach failed')
}

# ---------------------------------------------------------------------------
# vault-sync.ps1 -Action Stage / Commit
# ---------------------------------------------------------------------------

Write-Host "`n-- Action: Stage / Commit --"

$commitRepo = Join-Path $base 'commit-repo'
New-GitRepo -RepoPath $commitRepo
Write-RepoFile $commitRepo 'File.md' "one`n"
Add-CommitAll $commitRepo 'first'
Write-RepoFile $commitRepo 'File.md' "two`n"

Run-Test 'Stage stages changes and reports a diffstat' {
    $r = Invoke-Sync @('-Action', 'Stage', '-VaultRootOverride', $base, '-Path', 'commit-repo')
    $staged = (git -C $commitRepo diff --cached --name-only) -join "`n"
    ($staged -eq 'File.md') -and (Assert-OutputContains $r.Output 'File.md')
}

Run-Test 'Commit appends Generated-by trailer' {
    Invoke-Sync @('-Action', 'Commit', '-VaultRootOverride', $base, '-Path', 'commit-repo', '-Message', 'Update File.md') | Out-Null
    $msg = git -C $commitRepo log -1 --pretty=%B
    (Assert-OutputContains $msg 'Update File.md') -and (Assert-OutputContains $msg 'Generated-by: vault-sync')
}

Run-Test 'Commit ExtraBody lines appear between summary and trailer' {
    Write-RepoFile $commitRepo 'File.md' "three`n"
    Invoke-Sync @('-Action', 'Stage', '-VaultRootOverride', $base, '-Path', 'commit-repo') | Out-Null
    Invoke-Sync @('-Action', 'Commit', '-VaultRootOverride', $base, '-Path', 'commit-repo', '-Message', 'Resolve conflict', '-ExtraBody', 'Auto-resolved: File.md') | Out-Null
    $msg = git -C $commitRepo log -1 --pretty=%B
    (Assert-OutputContains $msg 'Auto-resolved: File.md') -and (Assert-OutputContains $msg 'Generated-by: vault-sync')
}

# ---------------------------------------------------------------------------
# vault-sync.ps1 -Action Pull
# ---------------------------------------------------------------------------

Write-Host "`n-- Action: Pull --"

Run-Test 'Pull reports UpToDate when nothing changed' {
    $pair = New-RemoteAndLocal -Name 'uptodate'
    $r = Invoke-Sync @('-Action', 'Pull', '-VaultRootOverride', $base, '-Path', "uptodate-local")
    Assert-OutputContains $r.Output 'PullStatus: UpToDate'
}

Run-Test 'Pull reports FastForward when remote moved ahead cleanly' {
    $pair = New-RemoteAndLocal -Name 'ff'
    $peer = Join-Path $base 'ff-peer'
    git clone -q $pair.Remote $peer 2>&1 | Out-Null
    git -C $peer config user.email test@test.com 2>&1 | Out-Null
    git -C $peer config user.name Test 2>&1 | Out-Null
    git -C $peer config commit.gpgsign false 2>&1 | Out-Null
    Write-RepoFile $peer 'Other.md' "peer file`n"
    Add-CommitAll $peer 'peer commit'
    git -C $peer push -q 2>&1 | Out-Null

    $r = Invoke-Sync @('-Action', 'Pull', '-VaultRootOverride', $base, '-Path', 'ff-local')
    Assert-OutputContains $r.Output 'PullStatus: FastForward'
}

Run-Test 'Pull reports MergedConflicts and lists the conflicted file' {
    $pair = New-RemoteAndLocal -Name 'conflict'
    $peer = Join-Path $base 'conflict-peer'
    git clone -q $pair.Remote $peer 2>&1 | Out-Null
    git -C $peer config user.email test@test.com 2>&1 | Out-Null
    git -C $peer config user.name Test 2>&1 | Out-Null
    git -C $peer config commit.gpgsign false 2>&1 | Out-Null
    Write-RepoFile $peer 'File.md' "peer-version`n"
    Add-CommitAll $peer 'peer edit'
    git -C $peer push -q 2>&1 | Out-Null

    Write-RepoFile $pair.Local 'File.md' "local-version`n"
    Add-CommitAll $pair.Local 'local edit'

    $r = Invoke-Sync @('-Action', 'Pull', '-VaultRootOverride', $base, '-Path', 'conflict-local')
    ($r.ExitCode -eq 0) -and (Assert-OutputContains $r.Output 'PullStatus: MergedConflicts') -and (Assert-OutputContains $r.Output 'File.md')
}

Run-Test 'Pull reports FailedNetwork for an unreachable remote' {
    $badRepo = Join-Path $base 'bad-remote-local'
    New-GitRepo -RepoPath $badRepo
    Write-RepoFile $badRepo 'File.md' "one`n"
    Add-CommitAll $badRepo 'first'
    git -C $badRepo remote add origin (Join-Path $base 'does-not-exist.git') 2>&1 | Out-Null
    git -C $badRepo branch --set-upstream-to=origin/master master 2>&1 | Out-Null

    $r = Invoke-Sync @('-Action', 'Pull', '-VaultRootOverride', $base, '-Path', 'bad-remote-local')
    ($r.ExitCode -eq 1) -and (Assert-OutputContains $r.Output 'PullStatus: FailedNetwork')
}

Run-Test 'Pull reports FailedOther for a non-network failure' {
    $pair = New-RemoteAndLocal -Name 'otherfail'
    Write-RepoFile $pair.Local 'Untracked.md' "not added`n"   # untracked file that would be overwritten by the incoming merge
    $peer = Join-Path $base 'otherfail-peer'
    git clone -q $pair.Remote $peer 2>&1 | Out-Null
    git -C $peer config user.email test@test.com 2>&1 | Out-Null
    git -C $peer config user.name Test 2>&1 | Out-Null
    git -C $peer config commit.gpgsign false 2>&1 | Out-Null
    Write-RepoFile $peer 'Untracked.md' "peer version`n"
    Add-CommitAll $peer 'peer adds Untracked.md'
    git -C $peer push -q 2>&1 | Out-Null

    $r = Invoke-Sync @('-Action', 'Pull', '-VaultRootOverride', $base, '-Path', 'otherfail-local')
    ($r.ExitCode -eq 1) -and (Assert-OutputContains $r.Output 'PullStatus: FailedOther')
}

# ---------------------------------------------------------------------------
# vault-sync.ps1 -Action SaveConflictVersion
# ---------------------------------------------------------------------------

Write-Host "`n-- Action: SaveConflictVersion --"

Run-Test 'SaveConflictVersion resolves to ours and saves theirs alongside' {
    $pair = New-RemoteAndLocal -Name 'save'
    $peer = Join-Path $base 'save-peer'
    git clone -q $pair.Remote $peer 2>&1 | Out-Null
    git -C $peer config user.email test@test.com 2>&1 | Out-Null
    git -C $peer config user.name Test 2>&1 | Out-Null
    git -C $peer config commit.gpgsign false 2>&1 | Out-Null
    Write-RepoFile $peer 'File.md' "remote-version`n"
    Add-CommitAll $peer 'remote edit'
    git -C $peer push -q 2>&1 | Out-Null

    Write-RepoFile $pair.Local 'File.md' "local-version`n"
    Add-CommitAll $pair.Local 'local edit'
    git -C $pair.Local pull --no-rebase 2>&1 | Out-Null   # leaves a real conflict, MERGE_HEAD present (--no-rebase: no pull.rebase config on a bare host)

    $r = Invoke-Sync @('-Action', 'SaveConflictVersion', '-VaultRootOverride', $base, '-Path', 'save-local', '-ConflictFile', 'File.md')

    $resolvedContent = [System.IO.File]::ReadAllText((Join-Path $pair.Local 'File.md'))
    $conflictFiles = @(Get-ChildItem $pair.Local -Filter '*CONFLICT*')
    $savedContent = if ($conflictFiles.Count -gt 0) { [System.IO.File]::ReadAllText($conflictFiles[0].FullName) } else { '' }

    ($r.ExitCode -eq 0) -and
    ($resolvedContent.Trim() -eq 'local-version') -and
    ($conflictFiles.Count -eq 1) -and
    ($savedContent.Trim() -eq 'remote-version')
}

# ---------------------------------------------------------------------------
# vault-sync.ps1 -Action Push
# ---------------------------------------------------------------------------

Write-Host "`n-- Action: Push --"

Run-Test 'Push sends a local commit to the remote' {
    $pair = New-RemoteAndLocal -Name 'push'
    Write-RepoFile $pair.Local 'File.md' "pushed-content`n"
    Add-CommitAll $pair.Local 'push me'

    $r = Invoke-Sync @('-Action', 'Push', '-VaultRootOverride', $base, '-Path', 'push-local')

    $remoteTip = git -C $pair.Remote log -1 --pretty=%s
    ($r.ExitCode -eq 0) -and (Assert-OutputContains $r.Output 'Pushed') -and ($remoteTip -eq 'push me')
}

Run-Test 'Push failure is reported' {
    $badPush = Join-Path $base 'bad-push-local'
    New-GitRepo -RepoPath $badPush
    Write-RepoFile $badPush 'File.md' "one`n"
    Add-CommitAll $badPush 'first'
    git -C $badPush remote add origin (Join-Path $base 'does-not-exist-push.git') 2>&1 | Out-Null

    $r = Invoke-Sync @('-Action', 'Push', '-VaultRootOverride', $base, '-Path', 'bad-push-local')
    ($r.ExitCode -eq 1) -and (Assert-OutputContains $r.Output 'Push failed')
}

} finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}

Write-TestSummary
