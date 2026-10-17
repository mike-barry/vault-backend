---
name: vault-lint
description: Scan and fix formatting and encoding issues across vault markdown files. Fixes typographic characters, whitespace, and filenames; detects broken wiki-links and markdown-format anchor links. Use when the user says "lint the vault", "run vault lint", "fix formatting", "fix dashes", "clean up the vault", or after ingesting a batch of external content (web, AI output, word processor). Also covers hard-wrapped (fixed-width) lines on explicit request ("fix hard-wrapped lines", "run the hard-wrap fix") — see step 8.
---

# Vault Lint

For each step below:
1. Run the preview/report command and capture its output.
2. If the output lists any files, show them to the user and ask for confirmation before applying.
3. Only run the apply command if the user confirms.
4. For report-only steps (no apply command), just show the output to the user.

After all steps, include a summary of what was fixed and what (if anything) needs manual attention.

---

## 1. Typographic Character Replacement

Replace non-standard characters with ASCII equivalents (see script for full list).

Preview:

```powershell
pwsh .claude/skills/vault-lint/scripts/fix-typographic-chars.ps1
```

Apply:

```powershell
pwsh .claude/skills/vault-lint/scripts/fix-typographic-chars.ps1 -Update
```

---

## 2. Trailing Whitespace

Strip trailing whitespace from all lines.

Preview:

```powershell
pwsh .claude/skills/vault-lint/scripts/fix-trailing-whitespace.ps1
```

Apply:

```powershell
pwsh .claude/skills/vault-lint/scripts/fix-trailing-whitespace.ps1 -Update
```

---

## 3. Broken Wiki-Links

Scan for `[[...]]` links where the target note does not exist in the vault. For each broken link, checks git history to determine if the file was renamed (suggests the new name), deleted, or never existed. Report findings only — do not auto-fix.

```powershell
pwsh .claude/skills/vault-lint/scripts/check-broken-wikilinks.ps1
```

Show the output to the user. No confirmation or apply step needed.

When reporting broken links, recommend a remedy based on the git history annotation:

- **`was renamed to 'X'`** — update the link to the new name `X`.
- **`was deleted`, and the link lives in an archived document** (under any `Archive/` folder) — recommend the **Broken-Link convention**: rewrite `[[Deleted-Note]]` as `[[Broken-Link|Deleted-Note]]`. The original name stays readable as display text, but the target becomes the `Broken-Link` sentinel (kept in the ignore list), so the dead reference is preserved as a historical record without the linter re-flagging it. Archived docs are a point-in-time record and should not be rewritten to erase the reference — this marks it instead. (For a live, non-archived doc, fix or remove the link rather than marking it.)
- **`no history found`** — the target likely never existed (a placeholder or typo); fix the name or add it to the ignore list if intentional.

Known-broken links that are intentional can be suppressed via the ignore list at `.vault/state/vault-lint/known-broken-wikilinks.txt`. When the user asks to ignore a broken link, ask whether the ignore should be:

- **Global** — the target is suppressed everywhere in the vault. Add the bare note name under the global section at the top of the file, before any `[path:...]` header.
- **Path-scoped** — the target is suppressed only when the link appears in a file under a specific vault folder. Add a `[path:vault/relative/prefix]` section header (e.g. `[path:Areas/Vault-Dev/]`) if one doesn't already exist for that prefix, then add the bare note name under it.

In both cases the entry is the target inside `[[...]]`, without path, `#anchor`, or `|alias`; `#` starts a comment. The report appends a count of how many links were suppressed via the list. The `Broken-Link` sentinel used by the convention above is already in the global section.

---

## 4. Markdown Anchor Links

Scan for markdown-format fragment links - `[Section Name](#section-name)` or `[Section Name](Other-Note#section-name)` - which Obsidian does not resolve as heading jumps (only `[[#Heading]]` / `[[Note#Heading]]` wikilinks do; see [[Document-Conventions]]'s "Internal Heading Links" section). Runs across the whole vault, including `.claude/skills`, since those docs suffer the same broken navigation. External links (`http:`, `https:`, `mailto:`, etc.) are never matched.

Preview:

```powershell
pwsh .claude/skills/vault-lint/scripts/check-markdown-anchor-links.ps1
```

Apply:

```powershell
pwsh .claude/skills/vault-lint/scripts/check-markdown-anchor-links.ps1 -Update
```

Each link is verified against the target file's actual headings before being rewritten, so most cases fix automatically. A link is left as-is and reported under "Needs manual review" when it can't be resolved with confidence: the target file isn't found, the target name matches more than one file in the vault, no heading matches the fragment, or more than one heading slugifies to the same fragment. Confirm the auto-fixable batch with the user before running `-Update`, same as the other apply steps; show the manual-review list to the user afterward - these need a human to pick the right heading or fix a stale reference, not a guess.

---

## 5. Filename Conventions

Check that filenames follow `Title-Case-With-Hyphens` conventions: no spaces, no underscores, each hyphen-separated word starts with an uppercase letter. Report findings only — do not auto-fix (renaming files would break wiki-links).

```powershell
pwsh .claude/skills/vault-lint/scripts/check-filename-conventions.ps1
```

Show the output to the user. No confirmation or apply step needed.

---

## 6. Frontmatter Schema Conformance

Validate the agent-facing `agent.*` / `nav.*` frontmatter layer against its schema: unknown keys, malformed `nav` entries (each must be a `link` *or* `folder` object carrying a `description`), malformed `agent.instructions` entries (discriminated bare string / `pinned:` / `use_skill:`+`when:`), `folder:` paths that don't resolve to a real directory, empty-field placeholders, and a `Tasks.md` missing its `use_skill: vault-tasks` directive. The check is **owned by the `vault-agent-frontmatter` skill** (the schema lives there) — this is just where it runs in a lint sweep. Frontmatter wiki-link resolution is already covered by step 3 above.

```powershell
pwsh .claude/skills/vault-agent-frontmatter/scripts/validate-frontmatter.ps1
```

Most violations are report-only — show them to the user. The check also surfaces **folder-note completeness** findings, where a folder note is missing an entry for a standard subfolder that exists on disk. Resolve these by their leading tag:

- **`Missing folder entry (auto-add) for standard folder '<name>'`** — a standard ephemeral folder (`Inbox`/`Archive`) exists but has no `folder:` entry. The finding includes a ready-to-insert block with house-style `description` / `load_when`. **Auto-fix:** insert that block into the note's `nav.contents` (place `folder:` entries after `link:` entries, per [[Document-Conventions]] / the frontmatter schema), confirm the batch with the user the same way as other apply steps, then write via the agent's file tools (this is a `vault-agent-frontmatter` edit — preserve all existing fields, never touch a `pinned:` or `use_skill:` entry).
- **`Corpus member without a link entry (resolve interactively)`** — the folder note does not reach a `Corpus/` note by link. `Corpus/` is per-member links, not a single `folder:` entry, so do **not** auto-add: ask the user whether to add a `link` for it (and with what `description` / `load_when`) or leave it unlinked. Reach is **transitive through an intermediate folder note**, so a member inside a `Corpus/` subfolder is normally routed to from that subfolder's own folder note rather than listed in the parent — when the finding names one, adding it to the intermediate is usually the right fix, not adding it to the parent.
- **`Unreferenced non-standard subfolder (resolve interactively)`** — a non-standard subfolder has no `link` or `folder:` entry. Ask the user how to proceed (add an entry, or confirm it is intentionally omitted) rather than guessing.

---

## 7. Provenance Frontmatter

Check that files under any `Archive/` folder carry both `doc.created:` and `doc.archived:` frontmatter (Check 1, auto-repairable) and carry no stale `use_skill:` `agent.instructions` entries (Check 4, auto-repairable), and that all vault content files carry `doc.created:` (Check 2, report-only) and `doc.type:` (Check 3, report-only). See [[Document-Conventions]] for the canonical `doc.*` schema. Missing dates are recovered from existing frontmatter, a filename date segment, or git history where possible (via the shared `Get-CreatedDate`/ `Get-ArchivedDate` helpers, also used by `vault-doc-archive`); anything unresolved is flagged for manual repair rather than guessed. `doc.type` has no recovery chain — Check 3 only reports, never guesses. A `use_skill:` entry routes live edits through its owning skill; an archived doc is frozen and never rewritten, so a surviving entry is stale drift — `vault-doc-archive` already strips these at archive time, so Check 4 mainly catches docs archived before that behavior existed or by a path that bypassed the skill. Folder notes and `Tasks.md`/top-level `Tasks/` dashboard files are excluded from all four checks; Guide docs (`.claude/guides/*`) are additionally excluded from Check 3 only, since `doc.type` isn't part of their schema.

Preview (all four checks):

```powershell
pwsh .claude/skills/vault-lint/scripts/check-provenance.ps1
```

Apply (Checks 1 and 4 only):

```powershell
pwsh .claude/skills/vault-lint/scripts/check-provenance.ps1 -Update
```

The output has four sections. Show all four to the user:

- **`Check 1: Archive Provenance`** — `Would repair: <file> (doc.created: X, doc.archived: Y)` lines list recoverable files; confirm the batch with the user, then run the apply command. `Manual resolution needed: <file> (missing: ...)` lines could not be recovered from git history — ask the user for the correct date and set it directly (via `inject-provenance.ps1` or a direct edit); do not guess.
- **`Check 2: Vault-Wide Created`** — report-only regardless of `-Update`. Show the list to the user; auto-repair for this check is a planned follow-up once the report has been reviewed, not something to apply now.
- **`Check 3: Vault-Wide Type`** — always report-only; there is no recovery chain to auto-repair from. Ask the user for the correct `doc.type` for each listed file and set it directly, same as an unresolved Check 2 date.
- **`Check 4: Stale Archived use_skill: Entries`** — `Would strip: <file>` lines list archived files carrying a stale `use_skill:` entry; confirm the batch with the user, then run the apply command. Bare and `pinned:` entries are never touched.

---

## 8. Hard-Wrap Fix (optional)

Not part of the default sweep above — only run this when the user explicitly asks (e.g. "fix hard-wrapped lines", "run the hard-wrap fix"). Load [fix-hard-wrap.md](fix-hard-wrap.md) and follow it.

---

## 9. Task Lines

Check every `Tasks.md` for lines the task system cannot use: unknown or legacy (`Active`) section headings, empty titles, checkboxes under Reminders, missing or duplicate IDs, missing created dates, a promoted link whose `Task-N` doc is missing, a `Task-N` doc with no line, and a done or cancelled symbol outside Done. Wraps `tasks.ps1 -Action check` from the `vault-tasks` skill, so the two never disagree about what a problem is. Report-only.

```powershell
pwsh .claude/skills/vault-lint/scripts/check-task-lines.ps1
```

Show the output grouped by code. Remedies belong to `vault-tasks`: `MissingId` and `MissingCreated` are fixed by its `backfill` verb, `LegacyHeading` by renaming the heading to `Sprint`, and the rest by hand through the skill. See [[Task-System]].

---
## Testing

The scripts have a unit-test suite. Run it after changing any lint script:

```powershell
pwsh .claude/skills/vault-lint/scripts/unit-tests.ps1
```

It writes fixtures to a temp folder and runs each script against only those files via the shared `-OverridePath` parameter (a vault-relative folder, e.g. `Areas/Research/Inbox`, that scopes a script to that folder instead of the whole vault). The suite is hermetic and cleans up after itself; it exits non-zero on failure.

The frontmatter check (step 6) is owned by `vault-agent-frontmatter` and has its own suite — run it after changing `validate-frontmatter.ps1`:

```powershell
pwsh .claude/skills/vault-agent-frontmatter/scripts/unit-tests.ps1
```
