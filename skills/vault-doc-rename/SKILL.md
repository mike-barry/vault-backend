---
name: vault-doc-rename
description: Rename or move a vault markdown file while keeping all [[wikilink]] references in sync. Use when the user says "rename", "move", or "rename this doc", or when called programmatically by another vault skill. Resolves a bare filename to its vault path automatically.
---

# Vault Doc Rename

Renames or moves a vault markdown file and updates every `[[wikilink]]` and `![[embed]]` that references it across the vault, via the `vault move` command (`vault.exe`, on the system PATH). Links with anchors (`[[Note#Section]]`), display text (`[[Note|Label]]`), embed markers, or any combination are handled. Only the link target is rewritten; the anchor, alias, and embed marker are preserved verbatim. Bare links are rewritten when the basename changed, path-qualified links whenever the path changed.

This skill has two entry points:

- **User-invoked**: the user names an old file and a new name (or path).
- **Programmatic**: called by `vault-doc-archive` with fully-resolved `OldPath` and `NewPath`. Skip to [[#Apply]], no confirmation needed.

## Command Shape

```bash
vault move --path <vault-relative-source> --destination <vault-relative-dest> --output json
```

A call without `--apply` runs the plan and validate phases, mutates nothing, and answers `"applied": false`. Adding `--apply` performs the move.

- `--output json` - always pass it, and parse the result as JSON.
- `--vault` - omit it, so the call operates on the configured default vault.
- `--kind` - omit it. It asserts `note` against `folder` as a fail-fast, and a doc rename is always a note.

There is no `--force` and no override of any kind. Every call exits non-zero on refusal and prints a `{code, message, data}` object (see [[#Error Handling]]).

## Resolve Source

`--path` takes a vault-relative path and does no name resolution of its own, so resolve the user's target to a path before calling. Use the agent's own glob tool rather than `vault glob`, which needs a working ripgrep deployment this skill does not otherwise depend on.

- If the user gave a full vault-relative path, use it as given.
- Otherwise glob the vault (`**/<Name>.md`) to locate the file.
  - Exactly one match - use its vault-relative path.
  - More than one match - use `AskUserQuestion` with the matching paths as options, then use the chosen path. Do not guess.
  - No match - tell the user no such file exists and stop, without calling the command.

Programmatic entry: `OldPath` is already a resolved vault-relative path, so pass it directly as `--path`.

## Resolve Dest

`--destination` takes a full vault-relative path, and you compose it.

A bare name lands at the vault root, so `--destination "Beta.md"` moves the file to `/Beta.md`. For a rename in place, join the source's folder to the new basename yourself. Renaming `Areas/Homelab/Inbox/Alpha.md` to "Beta" is `--destination "Areas/Homelab/Inbox/Beta.md"`.

The destination carries the source's `.md` extension, and nothing is inferred or converted. The user still says "rename it to Beta", and you send the full path ending in `Beta.md`. Never ask the user to supply the extension.

Two further constraints refuse the call outright:

- The destination's parent folder must already exist. A move creates no folder, so create a new destination folder first with `vault create --path <folder> --kind folder`.
- The basename must satisfy the vault's name grammar, which is groups of ASCII letters, digits, `+` and `&`, joined by single dashes, starting with an upper-case letter or a digit. Normalize the user's wording into that shape when you compose the destination, so `my notes` becomes `My-Notes.md`.

If the user asks for a different extension (`Notes.md` to `Notes.txt`), that is a file-type conversion, which `move` refuses and has no override for. Tell them the command cannot change what a file is, and stop.

Programmatic entry: `NewPath` is the fully-resolved destination and already carries `.md`, so pass it directly as `--destination`.

## Preview

Call `vault move` without `--apply` before confirming. This returns the same report the applying call returns, while mutating nothing.

- `applied: false` - confirms this was a plan. If a return you believe is a preview says `applied: true`, the move already happened, so report that rather than re-running it.
- `moved[]` - the paths the move produces. One entry for a note, and for a folder, every file relocated beneath it.
- `repaired_links[]` - every wikilink occurrence the move will rewrite, each `{path, line, from, to}`. The array length is the occurrence count, and the number of distinct `path` values is the "in M files" count. Two links on one line are two entries with the same `path` and `line`, so do not dedupe by line when counting occurrences.
- `pinned_links[]` - bystander links that will be pinned, in the same `{path, line, from, to}` shape. Show these before the user says yes.
- `content_hash` - the moved note's hash. Notes only, since a folder move has no such field.
- `folder_note` - on a folder move, the folder note's post-move path.
- `case_only: true` - the move changes only letter case.

Every validate-phase refusal fires on a preview exactly as it would on a real call, so a clean preview is also a validation pass.

Programmatic entry: skip the preview, because `vault-doc-archive` has already resolved and confirmed the operation.

## Confirm

Present the operation to the user (old path, new name or path, and the preview from [[#Preview]]) and ask for confirmation. Do not apply without an explicit yes, or a prior standing instruction to proceed without confirming.

## Apply

Call `vault move` again with the same `--path` and `--destination`, adding `--apply`:

```bash
vault move --path <source> --destination <dest> --apply --output json
```

Under a single write lock, the command resolves the source's shape, validates the destination, rewrites every reference, moves the file, and prints the JSON summary. The destination's parent is not created, and an absent one is refused (see [[#Resolve Dest]]).

Reference rewriting covers bare links when the basename changed, or when the move would otherwise have flipped their resolution, and path-qualified links whenever the path changed. Each rewritten target is emitted in canonical form, bare when the new name is unique vault-wide and the full path otherwise. Renaming into an already-occupied basename still succeeds. The moved file's links emit full-path, and any bystander bare link whose resolution the move would otherwise have flipped is pinned to its current target's full path. Ambiguity never fails a move.

Report the result from the returned object:

- `applied: true` - the move landed. A return carrying `applied: false` is a plan, and nothing happened.
- `repaired_links[]` - report as "N references updated across M files", N being the array length and M the distinct `path` count. Itemize when the user asked to see the files.
- `pinned_links[]` - when non-empty, surface it alongside the rewrite count and name the files. An empty array is the normal case and warrants no comment.
- `moved[]` - on a folder move, the full set of relocated files. Report the count rather than listing all of them unless asked.
- `case_only: true` - mention it, because a case-only rename looks like a no-op in most tooling.
- `asserted_authority[]` - operational detail, never surfaced to the user.

An empty `repaired_links[]` is a normal, complete result, meaning nothing linked to the doc.

## Error Handling

If the call fails, stop and report the error to the user verbatim, then diagnose from it. Do not work around the failure using alternative tools such as `Move-Item`, manual `git` commands, or filesystem operations. The command is the authoritative implementation, and agent improvisation risks leaving the vault inconsistent.

A refusal exits non-zero and prints `{code, message, data}`. A basename collision is not among the codes, because it succeeds via protective pinning (see [[#Apply]]). The codes this skill meets:

- `path_not_found` - nothing at the source path, which happens when it moved between [[#Resolve Source]] and the call. Report and re-resolve.
- `already_exists` - the destination path is occupied. Report and ask the user for a different destination.
- `parent_missing` - the destination's parent folder does not exist, and `data.parent` names it. Create it with `vault create --path <parent> --kind folder` and retry, or ask the user first if the folder's existence is itself the question.
- `invalid_path` - the path names no note, because the destination is missing `.md` or carries a different extension. When `data.suggested` is present it names the value that works, so retry once with it. A genuinely different extension is a conversion, so stop and explain (see [[#Resolve Dest]]).
- `invalid_name` - the basename is outside the vault's name grammar, and `data.suggested` carries an accepted spelling. Use it, or confirm the corrected name with the user when the suggestion changes meaning. Nothing moved.
- `wrong_kind` - a `--kind` assertion disagreed with the operand's shape. This skill omits `--kind`, so treat it as a bug in the call you built.
- `dependency_unavailable` - the search engine (ripgrep) could not start, so the reference scan cannot run and no move is possible. Nothing was mutated. Report the deployment fault and stop, without retrying and without moving the file by other means.

## Notes

- Do not use this skill to rename files outside the vault root.
- The reference scan is note-scoped and skips dot-directories (`.git`, `.obsidian`, `.claude`, ...), matching every other vault operation. Wikilinks inside those folders are not rewritten.
- The move is a filesystem move rather than a `git mv`, so nothing is staged or committed.
- For archiving a doc to `Archive/`, use `vault-doc-archive` instead. It calls this skill internally after resolving the destination path and name.
