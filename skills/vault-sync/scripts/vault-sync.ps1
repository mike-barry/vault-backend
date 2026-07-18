# vault-sync.ps1
# Git mechanics for the vault-sync skill. Each -Action is a deterministic transform or
# status report; trivial/non-trivial conflict judgment, commit message wording, and the
# "reattach refused, resolve by hand" escape hatch stay in the skill's prose - not here.
#
# Usage:
#   .\vault-sync.ps1 -Action Status -Path <vault-relative-repo-path>
#   .\vault-sync.ps1 -Action Reattach -Path <repo> -Branch <name>
#   .\vault-sync.ps1 -Action Stage -Path <repo>
#   .\vault-sync.ps1 -Action Commit -Path <repo> -Message <text> [-ExtraBody <lines>]
#   .\vault-sync.ps1 -Action Pull -Path <repo>
#   .\vault-sync.ps1 -Action SaveConflictVersion -Path <repo> -ConflictFile <relpath>
#   .\vault-sync.ps1 -Action Push -Path <repo>
#
# -Path is vault-relative ('.' for the vault root itself, '.claude' for the submodule).

param(
    [Parameter(Mandatory)][ValidateSet('Status', 'Reattach', 'Stage', 'Commit', 'Pull', 'SaveConflictVersion', 'Push')]
    [string]$Action,
    [string]$Path = '.',
    [string]$Branch,
    [string]$Message,
    [string[]]$ExtraBody,
    [string]$ConflictFile,
    [string]$VaultRootOverride
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot 'vault-sync-git.ps1')

$vaultRoot = if ($VaultRootOverride) { $VaultRootOverride.TrimEnd('\') + '\' } else { Get-VaultRoot $PSScriptRoot }
$repoPath = if ($Path -and $Path -ne '.') { Resolve-VaultPath -VaultRoot $vaultRoot -Path $Path } else { $vaultRoot.TrimEnd('\') }

if (-not (Test-Path $repoPath)) {
    Write-Error "Path does not exist: $Path"
    exit 1
}

function Write-KV {
    param([string]$Key, $Value)
    Write-Host "${Key}: $Value"
}

switch ($Action) {

    # -------------------------------------------------------------------
    'Status' {
        $head = Test-GitDetachedHead -RepoPath $repoPath
        $merge = Test-GitMidMerge -RepoPath $repoPath
        $porcelain = @(git -C $repoPath status --porcelain 2>$null)

        Write-KV 'Path' $Path
        Write-KV 'Detached' $head.Detached
        Write-KV 'Branch' ($head.Branch ?? '')
        Write-KV 'HeadShort' ($head.HeadShort ?? '')
        Write-KV 'UncommittedCount' $porcelain.Count
        if ($porcelain.Count -gt 0) {
            Write-Host 'Uncommitted:'
            $porcelain | ForEach-Object { Write-Host "  $_" }
        }
        Write-KV 'MidMerge' $merge.MidMerge
        if ($merge.MidMerge) {
            Write-Host 'UnmergedFiles:'
            $merge.UnmergedFiles | ForEach-Object { Write-Host "  $_" }
        }
        exit 0
    }

    # -------------------------------------------------------------------
    'Reattach' {
        if (-not $Branch) { Write-Error 'Reattach requires -Branch'; exit 1 }
        $out = (git -C $repoPath checkout $Branch 2>&1 | ForEach-Object { "$_" }) -join "`n"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Reattached: $Path -> $Branch"
            exit 0
        }
        Write-Host "Reattach failed:`n$out"
        exit 1
    }

    # -------------------------------------------------------------------
    'Stage' {
        git -C $repoPath add -A
        if ($LASTEXITCODE -ne 0) { Write-Error "git add failed (exit $LASTEXITCODE)"; exit 1 }
        $stat = (git -C $repoPath diff --cached --stat 2>&1 | ForEach-Object { "$_" }) -join "`n"
        if ($stat) {
            Write-Host "Staged:`n$stat"
        } else {
            Write-Host 'Staged: nothing to commit'
        }
        exit 0
    }

    # -------------------------------------------------------------------
    'Commit' {
        if (-not $Message) { Write-Error 'Commit requires -Message'; exit 1 }
        $parts = @($Message)
        if ($ExtraBody) { $parts += ($ExtraBody -join "`n") }
        $parts += 'Generated-by: vault-sync'
        $fullMessage = $parts -join "`n`n"

        $tmpFile = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText($tmpFile, $fullMessage, $Utf8NoBom)
            $out = (git -C $repoPath commit --file $tmpFile 2>&1 | ForEach-Object { "$_" }) -join "`n"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Commit failed:`n$out"
                exit 1
            }
            Write-Host "Committed:`n$fullMessage"
            exit 0
        } finally {
            Remove-Item -LiteralPath $tmpFile -ErrorAction SilentlyContinue
        }
    }

    # -------------------------------------------------------------------
    'Pull' {
        $result = Invoke-GitPull -RepoPath $repoPath
        Write-KV 'PullStatus' $result.Status
        if ($result.ConflictedFiles.Count -gt 0) {
            Write-Host 'ConflictedFiles:'
            $result.ConflictedFiles | ForEach-Object { Write-Host "  $_" }
        }
        Write-Host "Raw:`n$($result.Raw)"
        if ($result.Status -in @('FailedNetwork', 'FailedOther')) { exit 1 }
        exit 0
    }

    # -------------------------------------------------------------------
    'SaveConflictVersion' {
        if (-not $ConflictFile) { Write-Error 'SaveConflictVersion requires -ConflictFile'; exit 1 }
        $relPosix = $ConflictFile.Replace('\', '/')

        $theirs = (git -C $repoPath show ":3:$relPosix" 2>&1 | ForEach-Object { "$_" }) -join "`n"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Could not read remote (stage 3) version of ${ConflictFile}: $theirs"
            exit 1
        }

        $conflictRelPath = New-ConflictFilePath -RelPath $relPosix
        $conflictAbsPath = Join-Path $repoPath $conflictRelPath
        $conflictDir = Split-Path $conflictAbsPath -Parent
        if (-not (Test-Path $conflictDir)) { New-Item -ItemType Directory -Force -Path $conflictDir | Out-Null }
        [System.IO.File]::WriteAllText($conflictAbsPath, $theirs, $Utf8NoBom)

        git -C $repoPath checkout --ours -- $relPosix
        if ($LASTEXITCODE -ne 0) { Write-Error "git checkout --ours failed for $ConflictFile"; exit 1 }

        git -C $repoPath add -- $relPosix
        git -C $repoPath add -- $conflictRelPath
        if ($LASTEXITCODE -ne 0) { Write-Error "git add failed while staging conflict resolution"; exit 1 }

        Write-Host "Resolved to local version: $ConflictFile"
        Write-Host "Remote version saved as: $conflictRelPath"
        exit 0
    }

    # -------------------------------------------------------------------
    'Push' {
        $out = (git -C $repoPath push 2>&1 | ForEach-Object { "$_" }) -join "`n"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Pushed:`n$out"
            exit 0
        }
        Write-Host "Push failed:`n$out"
        exit 1
    }
}
