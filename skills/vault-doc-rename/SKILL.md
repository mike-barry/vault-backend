---
name: vault-doc-rename
description: Rename or move a vault markdown file while keeping all [[wikilink]] references in sync. Use when the user says "rename", "move", or "rename this doc", or when called programmatically by another vault skill. Resolves a bare filename to its vault path automatically.
---

# Vault Doc Rename

Renames or moves a vault markdown file and updates every `[[wikilink]]` and `![[embed]]` that references it across the vault, via the `mcp__vault__move` MCP tool. Links with anchors (`[[Note#Section]]`), display text (`[[Note|Label]]`), embed markers, or any combination are handled — only the link target is rewritten; the anchor, alias, and embed marker are preserved verbatim. Bare links are rewritten when the basename changed; path-qualified links whenever the path changed.

This skill has two entry points:

- **User-invoked**: the user names an old file and a new name (or path).
- **Programmatic**: called by `vault-doc-archive` with fully-resolved `OldPath` and `NewPath`. Skip to [[#Apply]] — no confirmation needed.

## Resolve Source

`mcp__vault__move` takes a **vault-relative path** as `Source` and does no name resolution of its own — resolve the user's target to a path before calling:

- If the user gave a full vault-relative path, use it as given.
- Otherwise glob the vault (`**/<Name>.md`) to locate the file.
  - Exactly one match — use its vault-relative path.
  - More than one match — use `AskUserQuestion` with the matching paths as options, then use the chosen path. Do not guess.
  - No match — tell the user no such file exists and stop; do not call the tool.

Programmatic entry: `OldPath` is already a resolved vault-relative path — use it directly as `Source`.

## Resolve Dest

`Dest` must **carry the source's extension** — the tool infers nothing and converts nothing. Construct the extension yourself; do not make the user type it.

- A bare name (no `/`) keeps the file in its current folder and renames only the basename.
- A name containing `/` is treated as a full vault-relative destination path. A leading `/` targets the vault root.
- **Append `.md` if the user's new name does not already end in it.** This skill renames markdown docs, so the source is always a `.md` note and the destination must be too. The user still says "rename it to Beta" — you send `Beta.md`. Never ask the user to supply the extension, and never echo the raw name back at them as if the tool had rejected it.
- If the user explicitly asks for a *different* extension (`Notes.md` → `Notes.txt`), that is a file-type conversion, which `move` refuses outright and has no override for. Tell them the tool cannot change what a file is, and stop — do not work around it.

Programmatic entry: `NewPath` is the fully-resolved destination and already carries `.md` — use it directly as `Dest`.

## Preview

Call `mcp__vault__move` with `Apply: false` before confirming. This runs the tool's plan and validate phases and returns the **complete report** — every field the real call returns — while mutating nothing. Use it to show the user exactly what will happen:

- `filesRewritten[]` — the files whose links the move will edit, named at the paths they will have *after* the move. `referencesRewritten` is the occurrence count across them.
- `referencesQualifiedProtectively` — bystander links that will be pinned.
- `namingWarnings`, `folderNoteRenamed`, `folderNoteOrphaned` — flags the user should see before saying yes.
- `applied: false` — confirms this was a plan, not a result. If a return you believe is a preview says `applied: true`, the move already happened; report that plainly rather than re-running it.

The preview is a faithful prediction: apart from `applied`, its fields match what the applying call returns. It is not a bypass either — every validate-phase refusal (`not_found`, `already_exists`, `readonly_targets`, `invalid_argument`) fires under `Apply: false` exactly as it would under a real call, so a clean preview is also a validation pass.

Programmatic entry: skip the preview — `vault-doc-archive` has already resolved and confirmed the operation.

## Confirm

Present the operation to the user — old path, new name/path, and the preview from [[#Preview]] — and ask for confirmation. Do not apply without an explicit yes (or a prior standing instruction to proceed without confirming).

## Apply

Call `mcp__vault__move` again, this time without `Apply` (it defaults to true — mutation is the point of the call):

- `Source`: the resolved vault-relative path from [[#Resolve Source]] (user-invoked), or the fully-resolved `OldPath` (programmatic).
- `Dest`: the extension-carrying name or path from [[#Resolve Dest]] (user-invoked), or the fully-resolved `NewPath` (programmatic).
- `Kind`, `Vault`: omit them. `Kind` is inferred from the source (a doc rename is always a `file`); omit `Vault` to use the default. There is no `Force` parameter — ambiguity is never an error, so there is nothing to override.

The tool, under a single write lock:

- Resolves the source's shape and computes the destination, creating destination-parent folders if they do not exist.
- Rewrites every `[[...]]` / `![[...]]` reference to the moved file — bare links when the basename changed (or when the move would otherwise have flipped their resolution), path-qualified links whenever the path changed — emitting each rewritten target in canonical form (bare when the new name is unique vault-wide, else the full path). Renaming into an already-occupied basename is not an error: the moved file's links emit full-path, and any bystander bare link whose resolution the move would otherwise have flipped is pinned to its current target's full path rather than left to silently re-resolve. Ambiguity is never a reason the move fails.
- Moves the file.
- Returns a JSON summary object.

Report the result from the returned object:

- `applied: true` — the move landed. (A return carrying `applied: false` is a plan; nothing happened. Never report a plan as a completed rename.)
- `referencesRewritten` — count of link occurrences updated; `filesRewritten[]` — the files they were in (its length is the "in M files" count).
- `referencesQualifiedProtectively` — when non-null, `{count, files}` of bystander bare links pinned to their current target's full vault path because the move would otherwise have changed what they resolve to. Surface this alongside the rewrite count, e.g. "2 bystander links were pinned to full paths to preserve their targets," and name the files.
- `pureMove: true` — the basename was unchanged (a pure folder move), so no bare-link rewrite ran; report it as a straight move.
- `namingWarnings` — if non-empty, the new name departs from the vault's `Title-Case-With-Hyphens` convention; pass the warning along (the move still succeeded).
- `folderNoteOrphaned: true` — the moved file was a folder note (`Foo/Foo.md`) renamed or moved away from its folder; flag it so the user can confirm that was intended.

Every write-class return also carries a fixed envelope, the same on every vault write tool:

- `filesSkippedUnreadable[]` — vault-relative paths of notes the reference scan could not read (vanished mid-scan, dangling link). Normally `[]`; when non-empty, name the files, since links inside them were **not** rewritten.
- `capabilitiesUsed` — always `[]` for `move`; nothing to report.
- `lockWarning` — **present only when it fires** (the write inherited a lock abandoned by a process that died mid-operation). Absent on a normal call, so test for its presence, not for a null. When present, pass it to the user verbatim — an earlier vault write may be torn.

## Error Handling

If the tool call errors, **stop and report the error to the user verbatim**, then diagnose from it. Do not attempt to work around the failure using alternative tools (e.g. `Move-Item`, manual `git` commands, or filesystem operations). The tool is the authoritative implementation; agent improvisation risks leaving the vault in an inconsistent state.

The tool returns structured `{code, message, data}` errors. There is no ambiguity-related error — a basename collision or duplicate-basename rename simply succeeds via protective pinning (see [[#Apply]]). The errors this skill routinely meets:

- **`not_found`** — nothing at the source path (e.g. it moved between [[#Resolve Source]] and the call). Report and re-resolve.
- **`already_exists`** — the destination path itself is already occupied (distinct from a basename collision elsewhere in the vault, which is not an error). Report and ask the user for a different destination.
- **`invalid_argument` for a missing or changed extension** — the destination did not carry the source's extension. This is a bug in how *you* built `Dest`, not something to hand to the user: the error's `data.suggestedDest` names the exact value that works, so retry once with it. If the user genuinely asked for a file-type conversion, stop and explain instead — `move` refuses conversions and has no override.
- **`kind_mismatch`** / other **`invalid_argument`** — report verbatim; these signal the source was not the expected shape, or the name/path is malformed (e.g. link-breaking characters in the new basename).

## Notes

- Do not use this skill to rename files outside the vault root.
- The reference scan is note-scoped and skips dot-directories (`.git`, `.obsidian`, `.claude`, ...), matching every other vault tool — wikilinks that live inside those folders are not rewritten.
- For archiving a doc to `Archive/`, use `vault-doc-archive` instead — it calls this skill internally after resolving the destination path and name.
