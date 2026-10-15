# vault-sync-git.ps1
# Git-plumbing helpers used only by vault-sync's own scripts. Not in _shared/ - no other
# skill orchestrates pull/push/commit/merge-conflict handling today. Promote to a
# _shared/vault-git.ps1 if a second skill ever needs this (see Skill-Dev.md).
# Dot-source: . (Join-Path $PSScriptRoot 'vault-sync-git.ps1')

# True when $RepoPath's HEAD is detached (not on a branch).
# Returns @{ Detached; Branch; HeadShort }. Branch is $null when detached.
function Test-GitDetachedHead {
    param(
        [Parameter(Mandatory)][string]$RepoPath
    )
    $branch = (git -C $RepoPath symbolic-ref -q --short HEAD 2>$null)
    $headShort = (git -C $RepoPath rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $headShort = $null }
    if ($branch) {
        return @{ Detached = $false; Branch = $branch; HeadShort = $headShort }
    }
    return @{ Detached = $true; Branch = $null; HeadShort = $headShort }
}

# True when $RepoPath has an unfinished merge (e.g. a prior vault-sync run was interrupted
# mid-conflict-resolution). Checks MERGE_HEAD in the real git-dir (works for submodules and
# worktrees, where .git is a file, not a directory) and falls back to scanning porcelain
# status for unmerged markers (UU/AA/DD/AU/UA/DU/UD) as a cross-check.
# Returns @{ MidMerge; UnmergedFiles }.
function Test-GitMidMerge {
    param(
        [Parameter(Mandatory)][string]$RepoPath
    )
    $gitDir = (git -C $RepoPath rev-parse --git-dir 2>$null)
    $mergeHeadPresent = $false
    if ($LASTEXITCODE -eq 0 -and $gitDir) {
        $gitDirAbs = if ([System.IO.Path]::IsPathRooted($gitDir)) { $gitDir } else { Join-Path $RepoPath $gitDir }
        $mergeHeadPresent = Test-Path (Join-Path $gitDirAbs 'MERGE_HEAD')
    }
    $unmerged = @(git -C $RepoPath status --porcelain 2>$null | Where-Object {
        $_.Length -ge 2 -and $_.Substring(0, 2) -in @('UU', 'AA', 'DD', 'AU', 'UA', 'DU', 'UD')
    } | ForEach-Object { $_.Substring(3) })
    return @{ MidMerge = ($mergeHeadPresent -or $unmerged.Count -gt 0); UnmergedFiles = $unmerged }
}

# Pure classifier - no git calls. Turns raw `git pull` output/exit code/conflicted-file
# list into one of: UpToDate, FastForward, MergedClean, MergedConflicts, FailedNetwork,
# FailedOther. Kept pure so it's unit-testable without a real remote.
function Get-GitPullClassification {
    param(
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][int]$ExitCode,
        [string[]]$ConflictedFiles = @()
    )
    if ($ExitCode -eq 0) {
        if ($Output -match 'Already up to date') { return 'UpToDate' }
        if ($Output -match 'Fast-forward') { return 'FastForward' }
        return 'MergedClean'
    }
    if ($ConflictedFiles.Count -gt 0 -or $Output -match 'CONFLICT') { return 'MergedConflicts' }
    if ($Output -match 'Could not resolve host|Connection timed out|Permission denied|[Aa]uthentication failed|fatal: unable to access|Could not read from remote repository') {
        return 'FailedNetwork'
    }
    return 'FailedOther'
}

# Runs `git pull` against $RepoPath and classifies the result.
# --no-rebase pins the skill's documented behaviour (fast-forward when possible, otherwise a
# merge commit) regardless of the machine's pull.rebase setting: with no setting at all,
# git 2.27+ refuses a divergent pull outright ("Need to specify how to reconcile divergent
# branches"), which is what happened on a Linux host with a bare global config.
# Returns @{ Status; ConflictedFiles; Raw }.
function Invoke-GitPull {
    param(
        [Parameter(Mandatory)][string]$RepoPath
    )
    $output = (git -C $RepoPath pull --no-rebase 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $exitCode = $LASTEXITCODE
    $conflicted = @()
    if ($exitCode -ne 0) {
        $conflicted = @(git -C $RepoPath diff --name-only --diff-filter=U 2>$null)
    }
    $status = Get-GitPullClassification -Output $output -ExitCode $exitCode -ConflictedFiles $conflicted
    return @{ Status = $status; ConflictedFiles = $conflicted; Raw = $output }
}

# Builds the "Filename [CONFLICT yyyyMMdd HHmm].md" sibling path for a conflicted file.
# -Now lets tests pin a deterministic timestamp.
function New-ConflictFilePath {
    param(
        [Parameter(Mandatory)][string]$RelPath,
        [datetime]$Now = (Get-Date)
    )
    # Normalize first: on Linux .NET does not treat '\' as a separator, so a backslash
    # path would keep its directories inside the "file name" and double them up.
    $rel  = $RelPath -replace '\\', '/'
    $dir  = Split-Path $rel -Parent
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($rel)
    $ext  = [System.IO.Path]::GetExtension($rel)
    $stamp = $Now.ToString('yyyyMMdd HHmm')
    $newName = "$stem [CONFLICT $stamp]$ext"
    if ($dir) { return (Join-Path $dir $newName) -replace '\\', '/' }
    return $newName
}
