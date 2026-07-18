# vault-test-common.ps1
# Shared test infrastructure for vault skill unit tests.
# Dot-source this file (after vault-common.ps1):
#   . (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')
#
# Conventions for caller scripts:
#   $worktreePath  — set by Initialize-TestWorktree; used by Reset-TestFolder
#   $testRoot      — set by Initialize-TestWorktree; used by file helpers
#   $script:passed / $script:failed — initialized here; incremented by Run-Test

$script:passed = 0
$script:failed = 0

# ---------------------------------------------------------------------------
# Worktree lifecycle
# ---------------------------------------------------------------------------

# Create a temporary git worktree at HEAD for test isolation.
# Returns @{ WorktreePath; TestRoot } and creates the initial test folder.
# Assign: $worktreePath = $ctx.WorktreePath; $testRoot = $ctx.TestRoot
function Initialize-TestWorktree {
    param(
        # Vault root directory.
        [Parameter(Mandatory)][string]$VaultRoot,
        # Name of the test subfolder to create inside the worktree.
        [string]$FolderName = '.skill-test-tmp'
    )
    $wt = Join-Path ([System.IO.Path]::GetTempPath()) "vault-skill-test-$(Get-Random)"
    Write-Host "Setting up test worktree at $wt ..."
    git -C $VaultRoot worktree add $wt HEAD 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create git worktree at $wt" }
    $root = Join-Path $wt $FolderName
    New-Item -ItemType Directory -Path $root | Out-Null
    return @{ WorktreePath = $wt; TestRoot = $root }
}

# Remove the worktree created by Initialize-TestWorktree.
function Remove-TestWorktree {
    param(
        # Vault root directory.
        [Parameter(Mandatory)][string]$VaultRoot,
        # Path of the worktree to remove, as returned by Initialize-TestWorktree.
        [Parameter(Mandatory)][string]$WorktreePath
    )
    Write-Host "`nRemoving test worktree ..."
    git -C $VaultRoot worktree remove $WorktreePath --force 2>&1 | Out-Null
}

# ---------------------------------------------------------------------------
# Per-test reset
# ---------------------------------------------------------------------------

# Unstage any git mv changes, remove all untracked test files, recreate the
# empty folder. References $worktreePath and $testRoot from the caller's scope.
function Reset-TestFolder {
    $rel = $testRoot.Substring($worktreePath.Length).TrimStart('\/')
    git -C $worktreePath reset HEAD -- $rel 2>&1 | Out-Null
    git -C $worktreePath clean -fd $rel 2>&1 | Out-Null
    if (-not (Test-Path $testRoot)) {
        New-Item -ItemType Directory -Path $testRoot | Out-Null
    }
}

# ---------------------------------------------------------------------------
# File helpers — reference $testRoot from the caller's scope
# ---------------------------------------------------------------------------

function New-TestFile {
    param(
        # Path relative to $testRoot (set by Initialize-TestWorktree).
        [string]$RelPath,
        # File content written as UTF-8 without BOM. Defaults to empty string.
        [string]$Content = ''
    )
    $abs = Join-Path $testRoot $RelPath
    $dir = Split-Path $abs -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($abs, $Content, $Utf8NoBom)
}

function Get-TestFileContent {
    param(
        # Path relative to $testRoot (set by Initialize-TestWorktree).
        [string]$RelPath
    )
    [System.IO.File]::ReadAllText((Join-Path $testRoot $RelPath))
}

# ---------------------------------------------------------------------------
# Assertions — return $true on pass, print + return $false on failure
# ---------------------------------------------------------------------------

# Assert a general boolean condition. Use for output checks and other non-file assertions.
# File-specific cases should use Assert-FileExists, Assert-FileContains, etc.
function Assert-That {
    param(
        # Display name for this assertion, shown in test output.
        [string]$Name,
        # The condition to evaluate; $true = pass, $false = fail.
        [bool]$Condition,
        # Optional detail shown on failure (e.g. actual output).
        [string]$Detail = ''
    )
    Write-Host "  $Name" -NoNewline
    if ($Condition) {
        Write-Host '  PASS' -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host ''
        if ($Detail) { Write-Host "  FAIL: $Detail" -ForegroundColor DarkGray }
        $script:failed++
    }
}

# Return $true if the file at $RelPath has no UTF-8 BOM.
function Test-NoBom {
    param(
        # Path relative to $testRoot (set by Initialize-TestWorktree).
        [string]$RelPath
    )
    $b = [System.IO.File]::ReadAllBytes((Join-Path $testRoot $RelPath))
    -not ($b.Length -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191)
}

function Assert-FileExists {
    param(
        # Path relative to $testRoot (set by Initialize-TestWorktree).
        [string]$RelPath
    )
    if (Test-Path (Join-Path $testRoot $RelPath)) { return $true }
    Write-Host "  FAIL: expected file to exist: $RelPath" -ForegroundColor Red
    return $false
}

function Assert-FileNotExists {
    param(
        # Path relative to $testRoot (set by Initialize-TestWorktree).
        [string]$RelPath
    )
    if (-not (Test-Path (Join-Path $testRoot $RelPath))) { return $true }
    Write-Host "  FAIL: expected file to not exist: $RelPath" -ForegroundColor Red
    return $false
}

function Assert-FileContains {
    param(
        # Path relative to $testRoot.
        [string]$RelPath,
        # Substring expected to appear in the file.
        [string]$Expected
    )
    $content = Get-TestFileContent $RelPath
    if ($content.Contains($Expected)) { return $true }
    Write-Host "  FAIL: '$RelPath' does not contain: $Expected" -ForegroundColor Red
    Write-Host "  Actual: $content" -ForegroundColor DarkGray
    return $false
}

function Assert-FileNotContains {
    param(
        # Path relative to $testRoot.
        [string]$RelPath,
        # Substring expected to be absent from the file.
        [string]$NotExpected
    )
    $content = Get-TestFileContent $RelPath
    if (-not $content.Contains($NotExpected)) { return $true }
    Write-Host "  FAIL: '$RelPath' should not contain: $NotExpected" -ForegroundColor Red
    return $false
}

function Assert-OutputContains {
    param(
        # Captured output string to search.
        [string]$Output,
        # Substring expected to appear in the output.
        [string]$Expected
    )
    if ($Output.Contains($Expected)) { return $true }
    Write-Host "  FAIL: output does not contain: $Expected" -ForegroundColor Red
    Write-Host "  Actual output: $Output" -ForegroundColor DarkGray
    return $false
}

# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

# Run a named test: reset the folder, execute the body, record pass/fail.
function Run-Test {
    param(
        # Display name for this test, shown in test output.
        [string]$Name,
        # Test body scriptblock; must return $true on pass or $false on failure.
        [scriptblock]$Body
    )
    Write-Host "  $Name" -NoNewline
    Reset-TestFolder
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

# Print pass/fail summary and exit non-zero on any failure.
function Write-TestSummary {
    $total = $script:passed + $script:failed
    $color = if ($script:failed -eq 0) { 'Green' } else { 'Red' }
    Write-Host "`n-- Results: $($script:passed)/$total passed --" -ForegroundColor $color
    if ($script:failed -gt 0) { exit 1 }
}
