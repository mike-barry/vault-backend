---
name: vault-doc-rename
description: Rename or move a vault markdown file while keeping all [[wikilink]] references in sync. Use when the user says "rename", "move", or "rename this doc", or when called programmatically by another vault skill. Resolves a bare filename to its vault path automatically.
---

# Vault Doc Rename

Renames or moves a vault markdown file and updates every `[[wikilink]]` that references it across the vault, via the `mcp__vault-mcp-server__rename_note` MCP tool. Wikilinks with anchors (`[[Note#Section]]`), display text (`[[Note|Label]]`), or both are handled. Path-qualified links are updated; bare links to an ambiguous basename are skipped with a warning.

This skill has two entry points:

- **User-invoked**: the user names an old file and a new name (or path).
- **Programmatic**: called by `vault-doc-archive` with fully-resolved `OldPath` and `NewPath`. Skip to [[#Apply]] — no confirmation needed.

## Resolve NewName

The tool's `Note` parameter already resolves a bare filename, a path-qualified name, or a full `[[wikilink]]` to its vault path — do not glob for it yourself.

- **NewName** — pass the user's new name through as given:
  - A bare name (no `/`) keeps the file in its current folder and renames only the basename.
  - A name containing `/` is treated as a full vault-relative destination path.
  - The `.md` extension is optional either way — the tool adds it.

## Confirm

Present the operation to the user before applying — old name/path and new name/path — and ask for confirmation. Do not apply without an explicit yes (or a prior standing instruction to proceed without confirming). The tool has no dry-run mode, so there is no itemized wikilink-diff preview available before applying; mention this if the user asks to see the changes first.

## Apply

Call `mcp__vault-mcp-server__rename_note`:

- `Note`: the old file — bare name, path-qualified name, or wikilink (user-invoked), or the fully-resolved `OldPath` (programmatic).
- `NewName`: the new name or path, per [[#Resolve NewName]] (user-invoked), or the fully-resolved `NewPath` (programmatic).
- `Vault`: omit to use the default vault.

The tool:
- Resolves `Note` to a vault path (throws `Note not found: <Note>` if nothing matches).
- Updates all wikilinks in the vault before moving the file.
- Creates the destination folder if it does not exist.
- Moves the file.
- Returns a summary: file renamed + N wikilinks updated in M files (+ K skipped, if any).

Report the summary to the user. If any links were skipped, list the affected files so the user can update them manually.

## Error Handling

If the tool call errors, **stop and report the error to the user verbatim**, then diagnose from it. Do not attempt to work around the failure using alternative tools (e.g. `Move-Item`, manual `git` commands, or filesystem operations). The tool is the authoritative implementation; agent improvisation risks leaving the vault in an inconsistent state.

**Ambiguous `Note`**: if resolution finds more than one file with the same basename, the tool throws `Ambiguous wikilink [[<name>]]: <path1>, <path2>, ...`. Use `AskUserQuestion` with the listed paths as options, then retry the call with the user's chosen full path as `Note`.

## Notes

- The tool covers every note in the vault, including files inside dot-folders (e.g. `.claude`) that carry wikilinks into vault content.
- Do not use this skill to rename files outside the vault root.
- For archiving a doc to `Archive/`, use `vault-doc-archive` instead — it calls this skill internally after resolving the destination path and name.
