---
name: vault-doc-archive
description: Archive a vault doc to the local Archive/ folder, preserving or adjusting the filename per convention, injecting provenance frontmatter, and updating all wikilink back-references. Use when the user says "archive this doc", "I'm done with this", "move this to archive", or when called programmatically.
---

# Vault Doc Archive

Moves a vault doc to its local `Archive/` folder, applies the correct filename convention, injects `doc.created` / `doc.archived` / `doc.type` frontmatter, and updates all `[[wikilink]]` back-references via `vault-doc-rename`.

**Date-significant types** (Meeting, Chat, Email) carry a date in their filename: `Title-YYYY-MM-DD.md`. All other types rely on frontmatter for provenance and move with no date added to the filename. A date already present in any filename is never stripped.

This skill has two entry points:

- **User-invoked**: the user names a doc to archive, optionally supplying a type and/or date. Follows a preview → confirm → apply flow.
- **Programmatic**: called by `vault-docs` (plan or idea flow) with a fully-resolved `OldPath`, `Type`, and optional `Date`. Skip directly to [[#Apply]] — no path resolution, type inference, or confirmation needed.

## Resolve Source Path

The user may supply a bare basename, partial path, or vault-relative path. Glob vault-wide for the file if a full path was not given. If multiple files match, use `AskUserQuestion` with the matching vault-relative paths as options. Resolve to a vault-relative path.

Source files may live in ad-hoc subfolders within `Inbox/` (e.g. `Inbox/Candidates/`). Resolve the path normally — the subfolder does not carry over to `Archive/`.

## Determine Type

Check in this order:

1. **Filename** — strip any leading `YYYY-MM-DD-` or trailing `-YYYY-MM-DD` date segment from the stem. Then:
   - If the **first** hyphen-delimited segment of the remaining stem looks like a type word (Title-Case, no digits), use it.
   - Else if the **last** hyphen-delimited segment looks like a type word, infer that type.
2. **Conversation context** — if the user named the type or it is clear from context, use it.
3. **Prompt** — if none of the above yield a type, or if the inferred type is not in the known list below, use `AskUserQuestion` with the known types (below) as options plus an "Other" fallback for a custom type. If the user picks a custom type, also ask (via `AskUserQuestion`, Yes/No) whether it is date-significant.

Known types and their date-significance:

| Type | Date in filename? |
|------|:-----------------:|
| Meeting | Yes |
| Chat | Yes |
| Email | Yes |
| Bug | Yes |
| Plan | No |
| Idea | No |
| Note | No |
| Research | No |
| Reading | No |
| Proposal | No |
| Issue | No |

Any Title-Case word is a valid type, but types not in this table are **unrecognized** and must be confirmed with the user before proceeding.

## Recover Creation Date

Used to populate the `doc.created` frontmatter field and, for date-significant types without a filename date, the filename date. Run the shared recovery chain:

```powershell
pwsh .claude/skills/vault-doc-archive/scripts/recover-created-date.ps1 -SourcePath <vault-relative-source-path>
```

This checks, in order: existing `doc.created` frontmatter, a leading/trailing filename date segment, then the git first-commit date (`git log --follow --diff-filter=A`) — the same chain `vault-lint`'s provenance check uses, via the shared `Get-CreatedDate` helper. Prints the recovered date, or nothing if none of those resolve.

If the script prints nothing, fall back to **today's date** — last resort; note in skill output that no creation date was found. This fallback is deliberately not part of the shared chain (which must never guess) — it is this flow's own policy, since an archive event needs *some* date to be usable.

## Compute Destination

**Destination folder**: `Archive/` is always a sibling of the source file's containing folder, regardless of any intermediate subfolders.

| Source path | Destination folder |
|---|---|
| `Areas/Vault-Dev/Inbox/Plan-My-Doc.md` | `Areas/Vault-Dev/Archive/` |
| `Areas/Vault-Dev/Inbox/Candidates/Idea-Foo.md` | `Areas/Vault-Dev/Archive/` |
| `Projects/MyProject/Inbox/My-Note.md` | `Projects/MyProject/Archive/` |

**New filename**: determined by whether the source already has a date and whether its type is date-significant.

| Condition | Action |
|---|---|
| Filename has **trailing** date (`Title-YYYY-MM-DD`) | Move as-is |
| Filename has **leading** date (`YYYY-MM-DD-Title`) | Flip to trailing: `Title-YYYY-MM-DD.md` |
| No date + **date-significant** type | Append recovered creation date: `Title-YYYY-MM-DD.md` |
| No date + **non-date-significant** type | Move as-is — no date added |

When a rename is needed (leading-date flip or date append), keep the stem otherwise intact — do not move or strip the type word from the title. Extract just the date segment and reattach it at the end.

Examples:

| Source filename | Type | New filename |
|---|---|---|
| `Plan-My-Doc.md` | Plan (no date-sig) | `Plan-My-Doc.md` (as-is) |
| `My-Meeting-Notes.md` | Meeting (date-sig) | `My-Meeting-Notes-2026-06-28.md` |
| `Very-Important-Meeting.md` | Meeting (inferred from tail, date-sig) | `Very-Important-Meeting-2026-06-28.md` |
| `2026-06-01-Chat-Notes.md` | Chat (date-sig) | `Chat-Notes-2026-06-01.md` (flip) |
| `Chat-Notes-2026-06-01.md` | Chat (date-sig) | `Chat-Notes-2026-06-01.md` (as-is) |
| `2026-06-14-Plan-Doc-System-Redesign.md` | Plan (no date-sig) | `Plan-Doc-System-Redesign-2026-06-14.md` (flip) |

## Inject Frontmatter

Before moving the file, write all three fields via the shared helper:

```powershell
pwsh .claude/skills/vault-doc-archive/scripts/inject-provenance.ps1 `
    -SourcePath <vault-relative-source-path> -CreatedDate <date-from-Recover-Creation-Date> -ArchivedDate <today's-date> -Type <type-from-Determine-Type>
```

- `doc.created: YYYY-MM-DD` — added only if not already present; pass the date resolved in [[#Recover Creation Date]] above (including the today fallback, if used).
- `doc.archived: YYYY-MM-DD` — always written (represents this archive event); pass today's date.
- `doc.type: <Type>` — added only if not already present; pass the type resolved in [[#Determine Type]] above. A file already carrying `doc.type` (written by its scaffolding skill) keeps that value untouched.

The script writes into the existing YAML frontmatter block, or creates one if absent, without reordering or reformatting other existing fields.

## Preview

Show the proposed operation before applying:

```
Archive: Areas/Vault-Dev/Inbox/Plan-My-Doc.md
     → Areas/Vault-Dev/Archive/Plan-My-Doc.md
Frontmatter: +doc.created: 2026-06-14  +doc.archived: 2026-06-28  +doc.type: Plan
```

Note any filename changes (leading-date flip, date append) and frontmatter additions — omit `+doc.type` from the preview line when the file already carries one, since Apply won't touch it. Ask for confirmation before applying.

## Apply

1. Inject `doc.created` / `doc.archived` / `doc.type` frontmatter into the source file in place, and strip any `use_skill:` `agent.instructions` entries — the routing directive goes stale once a doc is archived (frozen, never rewritten). Bare and `pinned:` entries are left untouched.
2. Create `Archive/` in the destination folder if it does not exist (no folder note needed).
3. Call `vault-doc-rename` at its **programmatic entry point** with the fully-resolved `OldPath` and `NewPath`. It handles the `git mv`, wikilink updates, and move atomically.
   - If the filename is unchanged (as-is move), `OldPath` and `NewPath` differ only in the folder segment — the rename script treats this as a folder move and skips wikilink rewriting since the basename is unchanged.
4. Report the result: file archived + N wikilinks updated in M files + K skipped.

If any wikilinks were skipped (ambiguous basename), list the affected files so the user can update them manually.

## Archive Compaction (on demand)

To roll up older `Archive/` files into date subfolders, run:

```powershell
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-doc-archive/scripts/compact-archive.ps1 `
    -ArchiveDir <vault-relative-path-to-Archive>
```

Pass `-WhatIf` to preview without making changes. This is a separate, on-demand operation — not part of the core archive flow.

The script performs two passes:

1. **Month rollup** — flat `*.md` files in `Archive/` whose date is from a prior month move into `Archive/YYYY-MM/`.
2. **Year rollup** — files in `Archive/YYYY-MM/` whose year is prior to the current year move into `Archive/YYYY/`; now-empty `YYYY-MM/` subfolders are removed.

Date source: trailing or leading filename date if present; falls back to the `doc.archived` frontmatter field. Files with no recoverable date are skipped with a warning.
