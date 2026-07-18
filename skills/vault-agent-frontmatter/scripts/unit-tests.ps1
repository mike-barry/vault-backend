# Unit tests for validate-frontmatter.ps1.
# Run: pwsh .claude/skills/vault-agent-frontmatter/scripts/unit-tests.ps1
#
# The script is invoked as a child process with -PathOverride and -VaultRootOverride
# pointing at a temporary git worktree, so tests are hermetic and never touch the live
# vault. Exits non-zero if any assertion fails.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$_skillDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $_skillDir '..' '_shared' 'vault-common.ps1')
. (Join-Path $_skillDir '..' '_shared' 'vault-test-common.ps1')

$vaultRoot = Get-VaultRoot $PSScriptRoot
$override  = '.fm-test-tmp'

$ctx          = Initialize-TestWorktree -VaultRoot $vaultRoot -FolderName $override
$worktreePath = $ctx.WorktreePath
$testRoot     = $ctx.TestRoot

# Invoke validate-frontmatter scoped to the worktree test folder.
function Invoke-Validate {
    $scriptPath = Join-Path $PSScriptRoot 'validate-frontmatter.ps1'
    $a = @('-NoProfile', '-File', $scriptPath, '-PathOverride', $override, '-VaultRootOverride', $worktreePath)
    (& pwsh @a 2>&1 | Out-String)
}

# Build a ---fenced frontmatter block from raw inner lines.
function Fm { param([string[]]$Lines) "---`n" + ($Lines -join "`n") + "`n---`n# Body`n" }

try {
    # ---- well-formed notes pass ----------------------------------------------
    Write-Host "`nvalidate-frontmatter.ps1 - clean notes"
    Reset-TestFolder
    New-TestFile 'Good-Folder.md' (Fm @(
        'nav.contents:',
        '  - link: "[[Some-Note]]"',
        '    description: "A durable note"',
        '    load_when: "details needed"',
        '  - folder: ".fm-test-tmp/Sub"',
        '    description: "An ephemeral scope"'
    ))
    New-TestFile 'Sub/Placeholder.md' 'x'   # makes .fm-test-tmp/Sub a real directory
    New-TestFile 'Agent-Note.md' (Fm @(
        'agent.instructions:',
        '  - "Load [[Some-Note]] when relevant"',
        '  - pinned: "Never exfil this."',
        '  - use_skill: "vault-tasks"',
        '    when: "editing this file"',
        '    note: "Do not hand-edit task entries."'
    ))
    New-TestFile 'No-Frontmatter.md' "# Just a body`nNo frontmatter here.`n"

    $out = Invoke-Validate
    Assert-That 'clean notes produce no violations' ($out -match 'No frontmatter schema violations found\.') $out

    # ---- unknown keys ---------------------------------------------------------
    Write-Host "`nunknown keys"
    Reset-TestFolder
    New-TestFile 'Bad-Key.md' (Fm @(
        'nav.contents:',
        '  - link: "[[X]]"',
        '    description: "d"',
        'agent.foo:',
        '  - "stray"',
        'nav.bogus: value'
    ))
    $out = Invoke-Validate
    Assert-That 'flags unknown agent.* key' ($out -match "Unknown frontmatter key 'agent\.foo'") $out
    Assert-That 'flags unknown nav.* key'   ($out -match "Unknown frontmatter key 'nav\.bogus'") $out

    # ---- malformed nav entries ------------------------------------------------
    Write-Host "`nmalformed nav entries"
    Reset-TestFolder
    New-TestFile 'Both.md' (Fm @(
        'nav.contents:',
        '  - link: "[[X]]"',
        '    folder: "Areas"',
        '    description: "has both"'
    ))
    New-TestFile 'Neither.md' (Fm @(
        'nav.contents:',
        '  - description: "no target"'
    ))
    New-TestFile 'NoDesc.md' (Fm @(
        'nav.contents:',
        '  - link: "[[X]]"',
        '    load_when: "x"'
    ))
    New-TestFile 'UnknownField.md' (Fm @(
        'nav.contents:',
        '  - link: "[[X]]"',
        '    description: "d"',
        '    group: "Ref"'
    ))
    New-TestFile 'BareString.md' (Fm @(
        'nav.contents:',
        '  - "just a string"'
    ))
    $out = Invoke-Validate
    Assert-That 'flags both link and folder' ($out -match "has both 'link' and 'folder'") $out
    Assert-That 'flags neither link nor folder' ($out -match "has neither 'link' nor 'folder'") $out
    Assert-That 'flags missing description' ($out -match "is missing 'description'") $out
    Assert-That 'flags unknown entry field' ($out -match "has unknown field 'group'") $out
    Assert-That 'flags bare-string nav entry' ($out -match 'is a bare string, expected a link/folder object') $out

    # ---- malformed agent.instructions entries ---------------------------------
    Write-Host "`nmalformed agent.instructions entries"
    Reset-TestFolder
    New-TestFile 'BothDiscriminators.md' (Fm @(
        'agent.instructions:',
        '  - pinned: "p"',
        '    use_skill: "vault-docs"'
    ))
    New-TestFile 'NeitherDiscriminator.md' (Fm @(
        'agent.instructions:',
        '  - note: "no discriminator"'
    ))
    New-TestFile 'PinnedExtraField.md' (Fm @(
        'agent.instructions:',
        '  - pinned: "p"',
        '    when: "editing this file"'
    ))
    New-TestFile 'SkillMissingWhen.md' (Fm @(
        'agent.instructions:',
        '  - use_skill: "vault-docs"'
    ))
    New-TestFile 'SkillExtraField.md' (Fm @(
        'agent.instructions:',
        '  - use_skill: "vault-docs"',
        '    when: "editing this file"',
        '    bogus: "x"'
    ))
    New-TestFile 'SkillWithNote.md' (Fm @(
        'agent.instructions:',
        '  - use_skill: "vault-docs"',
        '    when: "editing this file"',
        '    note: "extra detail"'
    ))
    $out = Invoke-Validate
    Assert-That 'flags both pinned and use_skill' ($out -match "has both 'pinned' and 'use_skill'") $out
    Assert-That 'flags neither pinned nor use_skill' ($out -match "has neither 'pinned' nor 'use_skill'") $out
    Assert-That 'flags unexpected field on pinned entry' ($out -match "\(pinned\) has unexpected field 'when'") $out
    Assert-That 'flags use_skill entry missing when' ($out -match "\(use_skill\) is missing 'when'") $out
    Assert-That 'flags unexpected field on use_skill entry' ($out -match "\(use_skill\) has unexpected field 'bogus'") $out
    Assert-That 'well-formed use_skill entry with note passes' ($out -notmatch 'SkillWithNote\.md') $out

    # ---- folder path resolution ----------------------------------------------
    Write-Host "`nfolder path resolution"
    Reset-TestFolder
    New-TestFile 'Resolves/Keep.md' 'x'
    New-TestFile 'GoodFolder.md' (Fm @(
        'nav.contents:',
        '  - folder: ".fm-test-tmp/Resolves"',
        '    description: "real dir"'
    ))
    New-TestFile 'BadFolder.md' (Fm @(
        'nav.contents:',
        '  - folder: ".fm-test-tmp/Nope-Missing"',
        '    description: "missing dir"'
    ))
    $out = Invoke-Validate
    Assert-That 'resolving folder path passes' ($out -notmatch 'GoodFolder\.md') $out
    Assert-That 'missing folder path flagged'  ($out -match 'folder path does not resolve' -and $out -match 'Nope-Missing') $out

    # ---- empty placeholders ---------------------------------------------------
    Write-Host "`nempty placeholders"
    Reset-TestFolder
    New-TestFile 'EmptyInline.md' (Fm @(
        'nav.contents:',
        '  - link: "[[X]]"',
        '    description: "d"',
        'nav.see_also: []'
    ))
    New-TestFile 'EmptyBlock.md' (Fm @(
        'agent.instructions:'
    ))
    $out = Invoke-Validate
    Assert-That 'flags inline empty list placeholder' ($out -match "Empty placeholder 'nav\.see_also: \[\]'") $out
    Assert-That 'flags empty block list'              ($out -match "Empty 'agent\.instructions'") $out

    # ---- Tasks.md skill directive -------------------------------------------
    Write-Host "`nTasks.md skill directive"
    Reset-TestFolder
    New-TestFile 'Has/Tasks.md' (Fm @(
        'agent.instructions:',
        '  - use_skill: "vault-tasks"',
        '    when: "editing this file"'
    ))
    New-TestFile 'Missing/Tasks.md' (Fm @(
        'agent.instructions:',
        '  - use_skill: "some-unrelated-skill"',
        '    when: "editing this file"'
    ))
    New-TestFile 'NoFm/Tasks.md' "# Tasks`nNo frontmatter.`n"
    # Archived Tasks.md has its use_skill: directive intentionally stripped at archive time
    # (vault-doc-archive / vault-lint step 7 Check 4) - must not be flagged as missing it.
    New-TestFile 'Archive/Old-Project/Tasks.md' "---`ndoc.created: 2020-01-01`ndoc.archived: 2020-02-01`n---`n# Tasks`n"
    $out = Invoke-Validate
    Assert-That 'Tasks.md with vault-tasks directive passes' ($out -notmatch 'Has\\Tasks\.md') $out
    Assert-That 'Tasks.md without directive flagged' ($out -match 'Missing\\Tasks\.md' -and $out -match "missing its agent\.instructions") $out
    Assert-That 'Tasks.md with no frontmatter flagged' ($out -match 'NoFm\\Tasks\.md') $out
    Assert-That 'archived Tasks.md without directive not flagged' ($out -notmatch 'Old-Project\\Tasks\.md') $out

    # ---- folder-note completeness: missing ephemeral folder entry -------------
    # A folder note (<Dir>/<Dir>.md) whose directory contains a standard ephemeral folder with
    # no matching folder entry should be flagged as auto-addable; one already declared passes.
    Write-Host "`nfolder-note completeness - missing ephemeral folder"
    Reset-TestFolder
    New-TestFile 'AreaA/AreaA.md' (Fm @(
        'nav.contents:',
        '  - link: "[[AreaA/Tasks]]"',
        '    description: "tasks"'
    ))
    New-TestFile 'AreaA/Inbox/Keep.md' 'x'      # Inbox/ exists on disk, no folder entry -> flagged
    New-TestFile 'AreaB/AreaB.md' (Fm @(
        'nav.contents:',
        '  - folder: ".fm-test-tmp/AreaB/Archive"',
        '    description: "done"'
    ))
    New-TestFile 'AreaB/Archive/Old.md' 'x'    # Archive/ exists AND is declared -> not flagged
    $out = Invoke-Validate
    Assert-That 'missing ephemeral folder flagged with auto-add block' (
        $out -match "AreaA\\AreaA\.md" -and $out -match "Missing folder entry \(auto-add\) for standard folder 'Inbox'" -and
        $out -match 'folder: ".fm-test-tmp/AreaA/Inbox"' -and $out -match 'load_when: "working on in-progress tasks or finding a specific artifact"') $out
    Assert-That 'declared ephemeral folder not flagged' ($out -notmatch "AreaB\\AreaB\.md") $out

    # ---- folder-note completeness: Corpus member without a link ------------------
    Write-Host "`nfolder-note completeness - Corpus member link"
    Reset-TestFolder
    New-TestFile 'AreaC/AreaC.md' (Fm @(
        'nav.contents:',
        '  - link: "[[Corpus/Linked-Doc]]"',
        '    description: "a linked corpus doc"'
    ))
    New-TestFile 'AreaC/Corpus/Linked-Doc.md' 'x'     # has a link entry -> not flagged
    New-TestFile 'AreaC/Corpus/Orphan-Doc.md' 'x'     # no link entry -> flagged
    $out = Invoke-Validate
    Assert-That 'unlinked Corpus member flagged' ($out -match "Corpus member without a link entry" -and $out -match 'Orphan-Doc\.md') $out
    Assert-That 'linked Corpus member not flagged' ($out -notmatch 'Linked-Doc\.md') $out

    # ---- folder-note completeness: unreferenced non-standard subfolder --------
    Write-Host "`nfolder-note completeness - non-standard subfolder"
    Reset-TestFolder
    New-TestFile 'AreaD/AreaD.md' (Fm @(
        'nav.contents:',
        '  - link: "[[Sub-Area/Sub-Area]]"',
        '    description: "a referenced subfolder note"'
    ))
    New-TestFile 'AreaD/Sub-Area/Sub-Area.md' 'x'  # referenced by link basename -> not flagged
    New-TestFile 'AreaD/Loose/Note.md' 'x'         # non-standard, unreferenced -> flagged
    $out = Invoke-Validate
    Assert-That 'unreferenced non-standard subfolder flagged' ($out -match "Unreferenced non-standard subfolder" -and $out -match "AreaD/Loose") $out
    Assert-That 'linked subfolder not flagged as unreferenced' ($out -notmatch 'AreaD/Sub-Area') $out
} finally {
    Remove-TestWorktree -VaultRoot $vaultRoot -WorktreePath $worktreePath
}

Write-TestSummary
