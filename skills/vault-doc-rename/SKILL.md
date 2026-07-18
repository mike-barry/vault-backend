---
name: vault-doc-rename
description: Rename or move a vault markdown file while keeping all [[wikilink]] references in sync. Use when the user says "rename", "move", or "rename this doc", or when called programmatically by another vault skill. Resolves a bare filename to its vault path automatically.
---

# Vault Doc Rename

Renames or moves a vault markdown file and updates every `[[wikilink]]` that references it across the vault. Wikilinks with anchors (`[[Note#Section]]`), display text (`[[Note|Label]]`), or both are handled. Path-qualified links are updated; bare links to an ambiguous basename are skipped with a warning.

This skill has two entry points:

- **User-invoked**: the user names an old file and a new name (or path).
- **Programmatic**: called by `vault-doc-archive` with fully-resolved `OldPath` and `NewPath`. Skip to [[#Apply]] — no path resolution or confirmation needed.

## Resolve Paths

1. **OldPath** — the user may supply a bare basename (`Old-Doc` or `Old-Doc.md`), a partial path, or a vault-relative path. Glob vault-wide for the file if a full path was not given. If multiple files match the basename, use `AskUserQuestion` with the matching vault-relative paths as options. Resolve to a vault-relative path (e.g. `Areas/Vault-Dev/Inbox/Plan-Old-Doc.md`).

2. **NewPath** — the user may supply just a new name or a full vault-relative path.
   - If only a name is given (no path separators), place the renamed file in the **same folder** as `OldPath`.
   - If a full path is given, use it as-is.
   - Ensure the extension is `.md`; add it if the user omitted it.

## Report

Run the script in report-only mode (no `-Update`) and show the output to the user:

```powershell
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-doc-rename/scripts/vault-rename.ps1 `
    -OldPath <vault-relative-old> `
    -NewPath <vault-relative-new>
```

The report lists every wikilink that would be updated or skipped. If the rename is a pure folder move (basename unchanged), the script notes that no wikilink changes are needed.

If the report shows skipped bare links (ambiguous basename), highlight this to the user so they know which files need manual review after the rename.

## Confirm

Present the report summary to the user and ask for confirmation before applying. Do not apply without an explicit yes (or a prior standing instruction to proceed without confirming).

## Apply

Run the script with `-Update` to apply changes:

```powershell
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-doc-rename/scripts/vault-rename.ps1 `
    -OldPath <vault-relative-old> `
    -NewPath <vault-relative-new> `
    -Update
```

The script:
- Updates all wikilinks in the vault before moving the file
- Creates the destination folder if it does not exist
- Moves the file
- Prints a summary: file renamed + N wikilinks updated in M files + K skipped

Report the summary to the user. If any links were skipped, list the affected files so the user can update them manually.

## Error Handling

If the script exits with an error, **stop and report the error to the user verbatim**, then diagnose from the output. Do not attempt to work around the failure using alternative tools (e.g. `Move-Item`, manual `git` commands, or filesystem operations). The script is the authoritative implementation; agent improvisation risks leaving the vault in an inconsistent state.

## Notes

- The script scans every `*.md` file in the repo, excluding files inside any folder whose name starts with a dot (`.claude`, `.myai`, etc.). All vault content is covered.
- Do not use this skill to rename files outside the vault root.
- For archiving a doc to `Archive/`, use `vault-doc-archive` instead — it calls this skill  internally after resolving the destination path and name.
