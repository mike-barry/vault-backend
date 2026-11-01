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

# ---- Get-PrunedFiles -------------------------------------------------------
Write-Host "`nGet-PrunedFiles"

$walk = Join-Path ([System.IO.Path]::GetTempPath()) "vault-common-walk-$(Get-Random)"
try {
    foreach ($rel in @('Tasks.md'), @('A', 'Tasks.md'), @('A', 'B', 'Tasks.md'), @('.hidden', 'Tasks.md'),
                     @('node_modules', 'x', 'Tasks.md'), @('A', 'archive', 'Tasks.md'), @('A', 'Other.md')) {
        $p = Join-Path $walk ($rel -join $sep)
        New-Item -ItemType Directory -Force -Path (Split-Path $p -Parent) | Out-Null
        [System.IO.File]::WriteAllText($p, '', $Utf8NoBom)
    }
    $resolvedWalk = (Resolve-Path $walk).Path
    $toRel = { param($list) (@(foreach ($x in $list) { $x.Substring($resolvedWalk.Length + 1) -replace '\\', '/' })) -join ',' }

    $got = & $toRel (Get-PrunedFiles -Root $walk -Filter 'Tasks.md' -ExcludeFolderNames 'node_modules', 'Archive')
    Assert-That 'prunes named folders case-insensitively, walks dot folders' ($got -ceq '.hidden/Tasks.md,A/B/Tasks.md,A/Tasks.md,Tasks.md') $got
    $got = & $toRel (Get-PrunedFiles -Root $walk -Filter '*.md')
    Assert-That 'no exclusions walks everything' (($got -split ',').Count -eq 7) $got
    $first = @(Get-PrunedFiles -Root $walk -Filter 'Tasks.md')[0]
    Assert-That 'returns absolute paths with the platform separator' ($first -eq (Join-Path $resolvedWalk '.hidden' 'Tasks.md')) $first
    Assert-That 'missing root returns nothing' (@(Get-PrunedFiles -Root (Join-Path $walk 'nope')).Count -eq 0)
} finally {
    Remove-Item -Recurse -Force $walk -ErrorAction SilentlyContinue
}

# ---- Get-VaultRelativePath -------------------------------------------------
Write-Host "`nGet-VaultRelativePath"

$root = Join-Path ([System.IO.Path]::GetTempPath()) 'vault-rel'
$got = Get-VaultRelativePath $root (Join-Path $root 'Areas' 'A' 'Tasks.md')
Assert-That 'path under the root is relative with /' ($got -ceq 'Areas/A/Tasks.md') $got
$got = Get-VaultRelativePath ($root + '/') (Join-Path $root.ToUpperInvariant() 'X.md')
Assert-That 'root with a trailing separator; prefix match ignores case' ($got -ceq 'X.md') $got
Assert-That 'the root itself is empty' ((Get-VaultRelativePath $root $root) -eq '') (Get-VaultRelativePath $root $root)
$outside = Join-Path ([System.IO.Path]::GetTempPath()) 'elsewhere' 'Y.md'
$got = Get-VaultRelativePath $root $outside
Assert-That 'path outside the root is absolute with /' ($got -ceq ($outside -replace '\\', '/')) $got
$got = Get-VaultRelativePath $root ($root + '-sibling')
Assert-That 'a sibling sharing the prefix is not under the root' ($got -ceq (($root + '-sibling') -replace '\\', '/')) $got

# ---- Test-ExcludedPathSegment ----------------------------------------------
Write-Host "`nTest-ExcludedPathSegment"

Assert-That 'a matching segment excludes, ignoring case'  (Test-ExcludedPathSegment 'Projects/P/archive/Tasks.md' @('Archive', '.git'))
Assert-That 'either separator splits'                     (Test-ExcludedPathSegment 'Projects\node_modules\x' @('node_modules'))
Assert-That 'a partial segment does not match'            (-not (Test-ExcludedPathSegment 'Projects/Archived/Tasks.md' @('Archive')))
Assert-That 'empty path and no names do not match'        (-not (Test-ExcludedPathSegment '' @('Archive')) -and -not (Test-ExcludedPathSegment 'Archive/x'))

# ---- Set-FileLines ---------------------------------------------------------
Write-Host "`nSet-FileLines"

$out = Join-Path ([System.IO.Path]::GetTempPath()) "vault-common-lines-$(Get-Random).md"
try {
    Set-FileLines -Path $out -Lines @('a', '- [ ] b') -LineEnding "`r`n"
    $bytes = [System.IO.File]::ReadAllBytes($out)
    Assert-That 'preserves CRLF with a trailing line ending' ([System.IO.File]::ReadAllText($out) -ceq "a`r`n- [ ] b`r`n")
    Assert-That 'writes no BOM' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191))
    Set-FileLines -Path $out -Lines @('x', '')
    Assert-That 'LF by default; an empty last line is kept' ([System.IO.File]::ReadAllText($out) -ceq "x`n`n")
    Set-FileLines -Path $out -Lines @()
    Assert-That 'an empty array writes an empty file' ((Get-Item $out).Length -eq 0)
} finally {
    Remove-Item $out -ErrorAction SilentlyContinue
}

# ---- ConvertTo-TitleSlug ---------------------------------------------------
Write-Host "`nConvertTo-TitleSlug"

$cases = [ordered]@{
    'Reconsider the task system'                 = 'Reconsider-The-Task-System'
    'Set up [[Util1]] & MCP/stdio for **iPhone**' = 'Set-Up-Util1-MCP-Stdio-For-IPhone'
    'See [[Plan-X|the plan]] and [doc](https://x.y/a#b)' = 'See-The-Plan-And-Doc'
    "Mike's  --  notes"                          = 'Mikes-Notes'
    "Mike$([char]0x2019)s notes"                 = 'Mikes-Notes'
    '~~**__~~'                                   = ''
}
foreach ($k in $cases.Keys) {
    $got = ConvertTo-TitleSlug -Text $k
    Assert-That "slug: $k" ($got -ceq $cases[$k]) $got
}
$got = ConvertTo-TitleSlug -Text 'alpha beta gamma delta' -MaxLength 16
Assert-That 'cuts on a word boundary within MaxLength' ($got -ceq 'Alpha-Beta-Gamma') $got
$got = ConvertTo-TitleSlug -Text 'supercalifragilistic word' -MaxLength 5
Assert-That 'over-long first word is cut to fit' ($got -ceq 'Super') $got

Write-TestSummary
