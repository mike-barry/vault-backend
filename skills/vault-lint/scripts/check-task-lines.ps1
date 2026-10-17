# Task-line lint: reports problems in Tasks.md files by wrapping the vault-tasks script's
# `check` verb, so the lint sweep and the task skill share one definition of a problem.
# Report-only; the fixes belong to the task verbs (`backfill` for missing IDs and created
# dates, a heading rename for a legacy `Active` section, and so on - see the skill).
#
# Codes, from tasks.ps1 -Action check: UnknownSection, LegacyHeading, EmptyTitle,
# CheckboxInReminders, MissingId, MissingCreated, DuplicateId, MissingDoc, OrphanDoc,
# DoneOutsideDone.
#
# The task script is located relative to this file, not the vault root, so a test worktree
# without the .claude submodule still finds it.
param(
    # Vault-relative folder to scope the scan (e.g. 'Areas/Personal'). When omitted, every
    # Tasks.md under the vault root is checked.
    [string]$PathOverride,
    # Vault root directory. Auto-resolved from the script location when not specified; pass
    # explicitly for non-default locations such as a test worktree.
    [string]$VaultRootOverride
)

. "$PSScriptRoot\lint-common.ps1"
$vaultRoot = if ($VaultRootOverride) { $VaultRootOverride } else { Get-VaultRoot $PSScriptRoot }

$tasksScript = Join-Path $PSScriptRoot '..' '..' 'vault-tasks' 'scripts' 'tasks.ps1'
if (-not (Test-Path $tasksScript)) {
    Write-Error "tasks.ps1 not found at $tasksScript"
    exit 1
}

$argList = @('-NonInteractive', '-NoProfile', '-File', $tasksScript, '-Action', 'check', '-VaultRootOverride', $vaultRoot)
if ($PathOverride) { $argList += @('-Path', $PathOverride) }

$raw = & pwsh @argList 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "tasks.ps1 -Action check failed: $($raw -join "`n")"
    exit 1
}

$problems = @(($raw | Out-String) | ConvertFrom-Json)

if ($problems.Count -eq 0) {
    Write-Host "No task line problems found."
    exit 0
}

$byCode = $problems | Group-Object Code | Sort-Object Name
foreach ($group in $byCode) {
    Write-Host "$($group.Name) ($($group.Count)):"
    foreach ($p in $group.Group) {
        $where = if ($null -ne $p.LineNumber) { "$($p.File):$($p.LineNumber)" } else { $p.File }
        Write-Host "  $where - $($p.Message)"
    }
}
Write-Host ""
Write-Host "$($problems.Count) task line problem(s) found."
