# vault-tasks: Init

Creates a `Tasks.md` in a single project or area folder. Load this file when the user says "init task files", "add a task file", or asks to initialize or create a task list for a specific project or area.

## Before You Begin

Ask for anything missing:

1. **Path** — vault-relative path to the project or area folder (e.g. `Projects/Maui-Trip-2026` or `Areas/Hobbies`)
2. **Scope** — `personal` or `work`; written into the `scope:` frontmatter field, which the task dashboard queries use to include the file

## Steps

### 1. Run the script

```
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-tasks/scripts/init-tasks.ps1 `
    -Path "<path>" -Scope "<personal|work>"
```

The script errors if `Tasks.md` already exists at that path — no need to check first.

### 2. Report the result

Confirm the file was created and state the name and scope it was seeded with.
