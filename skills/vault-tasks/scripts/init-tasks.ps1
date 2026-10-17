# init-tasks.ps1
# Creates a Tasks.md in the given project or area folder from the skill template.
# Errors if Tasks.md already exists.
#
# Usage:
#   pwsh -NonInteractive -NoProfile -File init-tasks.ps1 `
#       -Path Projects/Maui-Trip-2026

param(
    [Parameter(Mandatory)][string]$Path,
    # Override the vault root; used by unit tests to redirect to a temporary worktree.
    [string]$VaultRootOverride
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-common.ps1')

$VaultRoot   = if ($VaultRootOverride) { Format-VaultRoot $VaultRootOverride } `
               else { Get-VaultRoot -StartPath $PSScriptRoot }
$templateDir = Join-Path $_skillDir 'templates'

$absPath = Resolve-VaultPath -VaultRoot $VaultRoot -Path $Path

if (-not (Test-Path $absPath -PathType Container)) {
    Write-Error "Folder not found: $absPath"
    exit 1
}

$Name     = Split-Path $absPath -Leaf
$taskFile = Join-Path $absPath 'Tasks.md'

if (Test-Path $taskFile) {
    Write-Error "Tasks.md already exists: $taskFile"
    exit 1
}

$template    = [System.IO.File]::ReadAllText((Join-Path $templateDir 'Tasks-Template.md'), $Utf8NoBom)
$noteContent = $template `
    -replace '\{\{Name\}\}',  $Name

[System.IO.File]::WriteAllText($taskFile, $noteContent, $Utf8NoBom)

Write-Host "Created: $taskFile"
Write-Host "  Name:  $Name"
