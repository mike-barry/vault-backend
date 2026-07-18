---
name: vault-project-archive
description: Archive a completed project in the vault. Use when the user says a project is done, finished, or complete and wants to move it to the archive — phrases like "archive the X project", "X is done, let's archive it", "move X to archive". Handles task cleanup, creating Archive subfolders if needed, moving the project folder, and updating registry notes.
---

# Archive Vault Project

## Steps

### 1. Locate the project
Find the project folder under `Projects/`.

### 2. Review Tasks.md
Read the project's `Tasks.md` if it exists.

- If there are **open or in-progress tasks**, surface them to the user and use `AskUserQuestion` per task (or one multi-select question covering all of them) with options: mark complete, drop, or keep. Do not proceed until the user responds.
- If there are **no remaining open tasks**, `Tasks.md` will be deleted during the move (not carried over).

### 3. Move the project
Use `git mv` to move the entire project folder directly under `Archive/`:
```
git mv Projects/ProjectName Archive/ProjectName
```

If `Tasks.md` has no remaining tasks, delete it before or after the move:
```
git rm Archive/ProjectName/Tasks.md
```

### 4. Update registry notes

Hand off to the `vault-agent-frontmatter` skill to:
- **Remove** the project's `nav.contents` entry from `Projects/Projects.md`.
- **Add** a `nav.contents` entry for the project (with completion date in the description) to `Archive/Archive.md`.
