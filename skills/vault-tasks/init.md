# vault-tasks: Init

Creates a `Tasks.md` in a single project or area folder. Load this file when the user says "init task files", "add a task file", or asks to initialize or create a task list for a specific project or area.

## Before You Begin

Ask for anything missing:

- **Path** — vault-relative path to the project or area folder (e.g. `Projects/Maui-Trip-2026` or `Areas/Hobbies`)

## Steps

### 1. Run the script

```
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-tasks/scripts/init-tasks.ps1 -Path "<path>"
```

The script errors if `Tasks.md` already exists at that path — no need to check first.

### 2. Report the result

Confirm the file was created and state the name it was seeded with.
