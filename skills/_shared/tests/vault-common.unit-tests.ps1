# vault-common.unit-tests.ps1
# Direct unit tests for _shared/vault-common.ps1 (see Skill-Dev.md's Testing Shared Scripts
# section). Covers the root-resolution helpers, which are the platform-sensitive part: a
# hard-coded '\' here is what broke every skill script on Linux. Uses a throwaway temp
# directory, no vault worktree.
# Usage: pwsh .claude/skills/_shared/tests/vault-common.unit-tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' 'vault-test-common.ps1')
. (Join-Path $PSScriptRoot '..' 'vault-common.ps1')

$sep = [System.IO.Path]::DirectorySeparatorChar

# ---- Format-VaultRoot ------------------------------------------------------
Write-Host "`nFormat-VaultRoot"

$base = Join-Path ([System.IO.Path]::GetTempPath()) "vault-common-test-$(Get-Random)"
$want = $base + $sep

Assert-That 'appends the platform separator to a bare path'   ((Format-VaultRoot $base) -eq $want) (Format-VaultRoot $base)
Assert-That 'trailing forward slash is replaced, not doubled'  ((Format-VaultRoot ($base + '/')) -eq $want) (Format-VaultRoot ($base + '/'))
Assert-That 'trailing backslash is replaced, not doubled'      ((Format-VaultRoot ($base + '\')) -eq $want) (Format-VaultRoot ($base + '\'))
Assert-That 'mixed trailing separators collapse to one'        ((Format-VaultRoot ($base + '\/')) -eq $want) (Format-VaultRoot ($base + '\/'))
Assert-That 'result never contains a literal backslash-slash'  (-not ((Format-VaultRoot ($base + '\')) -like '*\/*'))

# ---- Get-VaultRoot ---------------------------------------------------------
Write-Host "`nGet-VaultRoot"

New-Item -ItemType Directory -Path $base | Out-Null
$savedProjectDir = $env:CLAUDE_PROJECT_DIR
try {
    New-Item -ItemType Directory -Path (Join-Path $base '.git') | Out-Null
    $sub = Join-Path $base 'Areas' 'Deep'
    New-Item -ItemType Directory -Path $sub | Out-Null
    $resolvedBase = (Resolve-Path $base).Path

    $env:CLAUDE_PROJECT_DIR = $null
    Assert-That 'walks up from a subfolder to the directory holding .git' ((Get-VaultRoot -StartPath $sub) -eq ($resolvedBase + $sep)) (Get-VaultRoot -StartPath $sub)

    # A submodule's .git is a file, not a directory; the walk must continue past it.
    $subRepo = Join-Path $base 'Sub'
    New-Item -ItemType Directory -Path $subRepo | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $subRepo '.git'), "gitdir: ../.git/modules/Sub`n", $Utf8NoBom)
    Assert-That 'skips a submodule .git file and keeps walking' ((Get-VaultRoot -StartPath $subRepo) -eq ($resolvedBase + $sep)) (Get-VaultRoot -StartPath $subRepo)

    $env:CLAUDE_PROJECT_DIR = $base + '/'
    Assert-That 'CLAUDE_PROJECT_DIR wins and is normalized' ((Get-VaultRoot -StartPath $sub) -eq ($base + $sep)) (Get-VaultRoot -StartPath $sub)

    $joined = Join-Path (Get-VaultRoot -StartPath $sub) 'Areas'
    Assert-That 'Join-Path on the result yields a plain path' ($joined -eq (Join-Path $base 'Areas')) $joined
} finally {
    $env:CLAUDE_PROJECT_DIR = $savedProjectDir
    Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
}

Write-TestSummary
