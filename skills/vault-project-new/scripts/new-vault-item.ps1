# new-vault-item.ps1
# Scaffolds a new project or area folder in the vault.
# Creates the item folder, standard subfolders (Inbox/Corpus/Archive), and the folder note.
# Follow-up agent steps: Tasks.md via vault-tasks, frontmatter + registry via vault-agent-frontmatter.
#
# Usage (project):
#   pwsh -NonInteractive -NoProfile -File new-vault-item.ps1 `
#       -Name My-Project -Type project -Description "One-liner" -Goal "Definition of done"
#
# Usage (area):
#   pwsh -NonInteractive -NoProfile -File new-vault-item.ps1 `
#       -Name My-Area -Type area -Description "One-liner" -AreaScope "What it covers"

param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][ValidateSet('project', 'area')][string]$Type,
    [Parameter(Mandatory)][string]$Description,
    # Written to ## Goal (projects) or ## Scope (areas) in the folder note.
    [Parameter(Mandatory)][string]$GoalOrScope,
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

$NamePattern = '^[A-Z0-9][a-zA-Z0-9]*(-[A-Z0-9][a-zA-Z0-9]*)*$'

# --- Validate ---
if ($Name -cnotmatch $NamePattern) {
    Write-Error "Name must be Title-Case-With-Hyphens (e.g. My-Project). Got: $Name"
    exit 1
}

# --- Resolve paths ---
$itemPath = if ($Type -eq 'project') {
    Join-Path $VaultRoot 'Projects' $Name
} else {
    Join-Path $VaultRoot 'Areas' $Name
}

if (Test-Path $itemPath) {
    Write-Error "Folder already exists: $itemPath"
    exit 1
}

# --- Create folder structure ---
$null = New-Item -ItemType Directory -Path $itemPath -Force
foreach ($sub in @('Inbox', 'Corpus', 'Archive')) {
    $subPath = Join-Path $itemPath $sub
    $null = New-Item -ItemType Directory -Path $subPath
    $null = New-Item -ItemType File -Path (Join-Path $subPath '.placeholder')
}

# --- Create folder note ---
$goalOrScopeHeader = if ($Type -eq 'project') { 'Goal' } else { 'Scope' }
$template    = [System.IO.File]::ReadAllText((Join-Path $templateDir 'folder-note.md'), $Utf8NoBom)
$noteContent = $template `
    -replace '\{\{Name\}\}',               $Name `
    -replace '\{\{Description\}\}',        $Description `
    -replace '\{\{GoalOrScope\}\}',        $goalOrScopeHeader `
    -replace '\{\{GoalOrScopeContent\}\}', $GoalOrScope
$notePath = Join-Path $itemPath "$Name.md"
[System.IO.File]::WriteAllText($notePath, $noteContent, $Utf8NoBom)

# --- Report ---
$relPath = $itemPath.Substring($VaultRoot.Length).TrimEnd('\/')
Write-Host "Created $Type`: $relPath"
Write-Host "  Folder note: $Name.md"
Write-Host "  Subfolders:  Inbox/  Corpus/  Archive/"
Write-Host "Next steps: vault-tasks (Tasks.md), vault-agent-frontmatter (frontmatter + registry entry)"
