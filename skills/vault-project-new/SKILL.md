---
name: vault-project-new
description: Create a new project or area in the vault — folder, folder note, task list, and registry entry. Use when the user says "create a new project", "set up a new project", "add a project", "create a new area", "add an area", or names a new project or area they want to start tracking.
---

# Vault New Project / Area

Creates a new project or area with all required scaffolding and registers it. Gather any missing information from the user before starting.

The folder structure and folder note are created by `scripts/new-vault-item.ps1`. Follow-up steps (Tasks.md and frontmatter/registry) are handled by other skills.

## Before You Begin

Ask the user for anything missing:

**For a project:**
1. **Name** — `Title-Case-With-Hyphens` (e.g. `Maui-Trip-2026`)
2. **Goal** — what the project aims to achieve and how you will know it is finished; goes in the `## Goal` section of the folder note
3. **Work-vs-Personal** — if not already clear from context, use `AskUserQuestion` with options `Work` / `Personal`; determines which task dashboard includes this project
4. **One-line description** — used in the folder note header and registry entry

**For an area:**
1. **Name** — `Title-Case-With-Hyphens`
2. **Scope** — what the area covers and the standards to maintain; goes in the `## Scope` section of the folder note
3. **One-line description** — used in the folder note header and registry entry

## Steps

### 1. Run the scaffold script

For a project:
```
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-project-new/scripts/new-vault-item.ps1 `
    -Name <Name> -Type project -Description "<description>" -GoalOrScope "<goal>"
```

For an area:
```
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-project-new/scripts/new-vault-item.ps1 `
    -Name <Name> -Type area -Description "<description>" -GoalOrScope "<scope>"
```

This creates:
- `Projects/<Name>/` or `Areas/<Name>/` — the item folder
- `Inbox/`, `Corpus/`, `Archive/` subfolders, each with a `.placeholder`
- `<Name>.md` — the folder note body with `## Goal` (projects) or `## Scope` (areas) filled in

### 2. Create the task list

Hand off to the `vault-tasks` skill to create `Tasks.md` in the new folder. For projects, pass the Work-vs-Personal (`personal` or `work`) so the task file gets the correct frontmatter.

### 3. Build frontmatter and register

Hand off to the `vault-agent-frontmatter` skill to:
- Add frontmatter to the new folder note (seed with a `nav.contents` entry for `Tasks.md`)
- Add a `nav.contents` entry for the new item to the parent registry:
  - Projects → `Projects/Projects.md`
  - Area → the relevant `Areas/<Parent>/<Parent>.md` folder note
