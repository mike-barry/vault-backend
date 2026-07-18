---
name: vault-agent-frontmatter
description: Author and maintain the agent-facing YAML frontmatter (the agent.* / nav.* layer) on vault notes. Use when creating a folder note, adding or changing a nav entry or agent instruction, or when another vault skill needs to write frontmatter without embedding the schema itself.
---

# Vault Frontmatter

The single procedure for writing and maintaining the agent-facing frontmatter layer - the `agent.*` and `nav.*` namespaces - on vault notes. Other vault skills hand off here instead of embedding frontmatter knowledge, so the schema lives in one place. The agent does all reads and writes directly with its file tools; this skill is the *how*, and [[Frontmatter-Schema]] is the authoritative *spec* (load it when you need the full field reference and rationale). Because the schema lives here, the **programmatic schema-conformance check also lives here** (`scripts/validate-frontmatter.ps1`); the `vault-lint` skill invokes it as its frontmatter section rather than re-encoding the schema.

## When to Use

- **Creating a folder note** - build its `nav.contents` (and `nav.see_also`, `agent.*` if needed) frontmatter.
- **Adding or changing** a single `nav` entry or `agent` instruction on an existing note.
- **Handed off from another skill** (`vault-docs`, `vault-project-new`, etc.) that needs to write frontmatter - it calls this skill rather than knowing the schema.

## Note Types

Two kinds of notes, distinguished by role:

- **Folder notes** - one per folder, named after the folder (e.g. `Personal/Personal.md`). Their job is to route an agent to children. Carry the full `nav.*` / `agent.*` routing layer in frontmatter; body is human content only.
- **Read-in-full destinations** - an agent reads the whole body as the answer. Two subtypes:
    - **Content notes** - reference material for humans: software notes, research, project content, how-tos.
    - **Guide and reference docs** - structural notes defining rules and processes (e.g. [[Vault-Guide]], [[Document-Conventions]], [[Vault-Organization]]).

[[Vault-Guide]] is the bootstrap entry point — read in full rather than navigated to.

When migrating an older note, *move* any body sections that belong in frontmatter (`nav.*` / `agent.*`) into frontmatter and *delete* them — never leave a note with both frontmatter and legacy body sections.

## Core Rules

These are the rules you apply every time; see [[Frontmatter-Schema]] for the complete spec.

- **Hub vs destination.** Only **folder notes** (navigation hubs, named after their folder) carry the routing layer in frontmatter. A **read-in-full destination** (content note, guide/reference doc) carries `nav.*` / `agent.*` *only* when it has genuine per-doc navigation or an intrinsic instruction - most carry none.
- **Instruction locality.** A rule that must hold no matter how an agent reaches the note (e.g. a sensitivity / no-exfil policy, or a skill-owned-file routing directive) lives in **that note's own** `agent.instructions`, as a `pinned:` or `use_skill:` entry, not on a parent. Routing hints that choose among children live on the **folder note**.
- **Presence means content.** Write a field only when it has content. Omit `agent.*` entirely when there are no instructions; omit `nav.see_also` when empty. Never write an empty placeholder (`nav.see_also: []`, `*No additional instructions.*`).

## Frontmatter Shape

Flat, dot-namespaced keys at the top of the file. `nav` entries are nested objects.

```yaml
---
agent.instructions:
  - "Load [[Family]] when the conversation involves Katie or the kids"
  - pinned: "This note holds sensitive info; never include its contents in an outbound message"
  - use_skill: "vault-tasks"
    when: "editing this file, or reading it to answer a question about its tasks"
nav.contents:
  - link: "[[Family]]"
    description: "Katie, Samantha, Nolah, parents, siblings"
    load_when: "family details needed"
  - folder: "Areas/Vault-Dev/Plan"
    description: "Active planning docs in flight"
    load_when: "looking for or working on an in-flight plan"
nav.see_also:
  - link: "[[Some-Related-Note]]"
    description: "Why it's relevant"
---
```

See [[Frontmatter-Schema]] for the full field reference (entry shapes, discriminators, and rationale).

## Authoring Procedure

### Build a folder note's frontmatter

1. **Enumerate children.** List the notes and subfolders in the folder.
2. **Classify each child entry:**
    - A single durable note -> a **`link`** entry. Use the minimal link path that *resolves*: bare `[[Name]]` when the basename is unique; path-qualified `[[Corpus/Doc]]` only when the path encodes a group or is needed to disambiguate. A qualified link must be a real path *suffix* of the target file - a folder note is `<Folder>/<Folder>.md`, so link it as `[[Projects/Projects]]`, never `[[Projects]]` (a folder path that does not resolve). Same-basename folder notes across PARA (e.g. `Personal`/`Work` under `Areas/`) need the **full** vault path to be unambiguous.
    - A folder of *ephemeral* artifacts (`Inbox/`, `Archive/`) -> a single **`folder`** entry with the repo-relative path. **Never** spotlight an individual file inside such a folder as its own `link` - the folder entry covers it.
3. **Write `description` and `load_when`** for each entry. `load_when` is a **bare condition** (`"vision details needed"`), never an imperative (`"load when..."`).
4. **Place instructions by locality.** Routing hints among children -> a bare-string `agent.instructions` entry on this folder note. An intrinsic policy that must hold regardless of path -> a `pinned:` entry on the **child note's own** `agent.instructions`, not here.
5. **Omit empties.** No `nav.see_also: []`, no empty `agent.*`.

### Add or change one entry / instruction

1. **Read the file** and parse its existing frontmatter (it is plain YAML at the top).
2. **Preserve everything already there.** Add or modify only the target entry/instruction; do not reorder, reformat, or drop sibling fields - especially never touch a `pinned:` or `use_skill:` entry unless explicitly adding one.
3. **Re-emit** the frontmatter block followed by the unchanged body.

### Skill-owned files (e.g. `Tasks.md`)

A file whose format is owned by a skill carries a `use_skill:` entry in `agent.instructions` (`use_skill: "<skill>"`, `when:`, optional `note:`). When you rewrite such a file, **preserve that entry** - the file's whole point is to tell agents to use that skill.

**Write it by calling `Add-AgentInstructionEntry`, not by hand-typing the YAML.** The function lives in `_shared/vault-frontmatter.ps1` and is shared by every authoring skill (`vault-docs`, `vault-tasks`, ...) so the entry's exact shape is defined once, not re-typed per call site:

```powershell
. .claude/skills/_shared/vault-frontmatter.ps1
$content = Get-Content -Raw -LiteralPath $docPath
$content = Add-AgentInstructionEntry -Content $content -Type UseSkill -UseSkill 'vault-docs' -When 'editing this file'
Set-Content -NoNewline -LiteralPath $docPath -Value $content
```

Idempotent - safe to call unconditionally (e.g. during a backfill) without checking whether the entry is already present.

**Each consuming skill owns a thin wrapper script over this call, not a prose pointer to it.** A flow doc that just said "see this pattern" would force an agent to invoke the `Skill` tool on `vault-agent-frontmatter` — loading this entire `SKILL.md` — just to inject 2-3 fixed lines, defeating the point of extracting the logic. Instead, the consuming skill puts a small `scripts/<verb>.ps1` in its own folder that dot-sources `_shared/vault-frontmatter.ps1` and fixes `-UseSkill` to itself; its flow docs then name that script directly (see `vault-docs/scripts/add-skill-directive.ps1` for the reference shape) - runnable via Bash/PowerShell with no `Skill`-tool hop at all.

## Reference Examples

- `Areas/Personal/Personal.md` - area folder note, all `link` entries; sensitivity rules live on the `Family` / `Medical` leaf notes (instruction locality), not here.
- `Areas/Vault-Dev/Vault-Dev.md` - mixes a `Corpus/` collection (path-qualified `link` entries) with `folder` entries for the ephemeral `Inbox/` / `Archive/` scopes.
- `Projects/New-RTP-Interface/New-RTP-Interface.md` - project folder note with `Inbox/` / `Archive/` folder entries plus a durable `Project-Context` link.

## Relationship to Other Skills

- **[[Frontmatter-Schema]]** - the authoritative spec this skill applies. Load it for the full field reference and rationale.
- **`scripts/validate-frontmatter.ps1`** (co-located) - the programmatic schema-conformance check, owned here because the schema is. Deterministic checks only (valid keys, well-formed `nav` entries and `agent.instructions` entries, `folder:` path resolution, no empty placeholders, the `Tasks.md` `use_skill:` directive, and folder-note **completeness** - standard subfolders on disk that lack an entry, see the schema's *Standard-Folder Completeness*); subjective body-content detection is out of scope. Report-only - any auto-add is applied by `vault-lint` via the agent. Has its own hermetic `scripts/unit-tests.ps1`.
- **`vault-lint`** - runs `validate-frontmatter.ps1` as its frontmatter section in a lint sweep, and covers frontmatter wiki-link resolution via its `check-broken-wikilinks.ps1`. It calls this skill's script; it does not re-encode the schema.
- **Authoring skills** (`vault-docs`, `vault-project-new`, `vault-project-archive`) - hand off here to write frontmatter rather than embedding the schema.
