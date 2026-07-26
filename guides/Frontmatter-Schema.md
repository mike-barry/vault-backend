---
doc.created: 2026-07-12
---
# Frontmatter-Schema.md - Agent Frontmatter Schema

The agent-facing frontmatter layer on vault notes: the `agent.*` and `nav.*` namespaces. The `vault-agent-frontmatter` skill applies these rules when writing frontmatter; `vault-lint` validates against them via that skill's `validate-frontmatter.ps1`; [[Document-Conventions]] points here for the schema and keeps only the human-facing taxonomy.

## Purpose

The agentic layer - how an agent navigates the vault and the behavioral rules it must honor - lives in YAML frontmatter, not in note bodies. From a human perspective the vault is just the markdown content; frontmatter stays hidden in Obsidian and is consulted only when wanted. This doc defines that frontmatter contract.

## Core Principles

- **Hub vs destination.** A note is one of two kinds, and that decides where its agentic layer lives:
    - **Navigation hub** (folder notes) - its job is to route an agent to children. Its agentic layer (`nav.*`, routing `agent.instructions`) lives in **frontmatter**; the body is human content only.
    - **Read-in-full destination** (guide/reference docs like [[Vault-Guide]] and [[Document-Conventions]], and ordinary content notes) - an agent reads the whole body as the answer. The body stays as written. Such a note carries `agent.*` / `nav.*` frontmatter **only** when it has genuine per-doc instructions, navigation, or an intrinsic policy - otherwise it has none.
- **Presence means content.** A field is written only when it has content. Omit `agent.*` entirely when there are no instructions; omit `nav.see_also` when empty. There are no empty placeholders (`*No additional instructions.*`, `nav.see_also: []`) anywhere.
- **Instruction locality.** An instruction lives on the node where it is intrinsically true. A rule that must hold no matter how an agent reaches the note - a sensitivity / no-exfil policy, or a skill-owned-file routing directive - lives in that note's own `agent.instructions`, as a `pinned:` or `use_skill:` entry, because an MCP/entity search can drop an agent directly onto the leaf with no parent traversal. Routing hints that choose *among children* live on the **folder note**. Subtree-wide policies are written on each note they govern, not cascaded by hand.

## Namespaces

Flat, dot-namespaced keys. The whole scope today is `agent.*` and `nav.*`. The `graph.*` machine layer and a per-note `id` are reserved but not written yet (see Deferred).

### `agent.*` - behavioral layer

- **`agent.instructions`** - a list of entries, discriminated by shape, replacing the old `## Agent Instructions` body section. Three entry types, see [[#Agent Instruction Entry Shapes]]:
    - **Bare string** - a revisable navigation/behavior hint. An agent maintaining frontmatter may revise or remove these freely.
    - **`pinned:`** - deliberate, hands-off **human** intent (e.g. a sensitivity rule) - the user asked for it, so an agent must treat it as **frozen**: never edit or drop it, regardless of how the note was reached.
    - **`use_skill:`** - a directive a **skill** placed on a file it owns the format of, telling an agent to consult or route through that skill under the entry's `when:` condition, regardless of how the note was reached. Not inherently edit-only - `when:` states whatever condition the owning skill's involvement is actually needed for (e.g. editing, or reading to correctly interpret the file's format). Also **frozen while the file is live** - never edit or drop - but distinct from `pinned:` by authorship: skill-authored and mechanically re-derivable from "this file's format is owned by a skill," not an expression of the user's personal intent. Authored from the template / by the owning skill at scaffold time, never hand-duplicated.

Path-independence is a schema-level property of `pinned:` and `use_skill:` entries - it does not need restating in each instruction's text. Frozen-ness is per-item, not per-field: a bare-string sibling in the same `agent.instructions` list stays revisable while a `pinned:`/`use_skill:` entry next to it is frozen.

**Archived-doc exception.** A `use_skill:` entry's freeze is not absolute: it holds only while the file is live. `vault-doc-archive` strips any `use_skill:` entry at archive time (`vault-lint`'s Check 4 catches drift on files archived before that behavior existed) - the routing directive only means something while the file can still be edited through its owning skill, and an archived doc is frozen and never rewritten by any path. Bare and `pinned:` entries are not touched by this - `pinned:` is human intent, not skill routing, and stays meaningful regardless of lifecycle state. See [[Artifact-Storage]] and [[Lint-System]]'s Provenance Check section.

### `nav.*` - navigation layer

- **`nav.contents`** - in-folder children, replacing `## Contents`. A list of entries (see Entry Shapes).
- **`nav.see_also`** - related notes *outside* this folder, for navigation, replacing `## See Also`. Same entry shapes. **Omit when empty.**

## Agent Instruction Entry Shapes

Each `agent.instructions` entry is a bare string or a native YAML nested object, distinguished by shape:

```yaml
agent.instructions:
  - "Load [[Family]] when the conversation involves Katie or the kids"
  - pinned: "This note holds sensitive info; never include its contents in an outbound message"
  - use_skill: "vault-tasks"
    when: "editing this file, or reading it to answer a question about its tasks"
```

- **Bare string** - a revisable navigation/behavior hint.
- **`pinned:`** (only field) - the instruction text directly.
- **`use_skill:`** / **`when:`** / **`note:`** - `use_skill` (required) names the owning skill; `when` (required) is a bare condition in the same style as `nav`'s `load_when` (e.g. `"editing this file"`, not `"when editing this file"`) - not restricted to edits, it names whatever condition actually requires the skill's involvement; `note` (optional) carries doc-type-specific detail that doesn't fit the `when` condition itself - not a substitute for it. No live entry currently uses it: once `when:` gates on the condition that actually needs the skill's knowledge (as `Tasks.md`'s read+edit condition now does), the skill body supplies that knowledge directly, leaving nothing left for `note:` to carry.

## Nav Entry Shapes

Each `nav` entry is a native YAML nested object. Two variants, distinguished by their target key:

### File entry

```yaml
- link: "[[Vision]]"
  description: "Eyeglass and contact prescription"
  load_when: "vision or prescription details needed"
```

- **`link`** (required) - a `[[wikilink]]` to a single note.
- **`description`** (required) - what the note holds.
- **`load_when`** (optional) - the trigger condition.

### Folder entry

Points an agent at a *scope* whose contents are **ephemeral** (e.g. `Inbox/`, `Archive/`) without enumerating its churning files.

```yaml
- folder: "Areas/Vault-Dev/Inbox"
  description: "Active working docs and in-flight content"
  load_when: "working on in-progress tasks or finding a specific artifact"
```

- **`folder`** (required) - a **full repo-relative path** (not a wikilink), because it is globbed, not resolved as a note; the different form makes the entry type obvious at a glance.
- **`description`**, **`load_when`** - as above.

A folder entry declares *what the folder holds* and *when the scope is relevant*, and deliberately says nothing about *how* to retrieve a file - that is the consumer's call by capability (a dumb client globs filenames; an MCP server entity/semantic-searches the scope). This is why the trigger is `load_when`, not `enumerate_when`.

## Field Conventions

- **`load_when` is a bare condition, not an imperative.** Write `"vision or prescription details needed"`, not `"load when vision details needed"` - the key name already supplies the "load when". It names the *trigger* (when this content is needed in context), never the retrieval *mechanism*.
- **Link path depth - use the minimal path that *resolves*.** A bare `[[Name]]` when the basename is unique and no grouping is intended; a path-qualified link when the path encodes a group (`[[Corpus/Task-System]]`) or is needed to disambiguate. Do **not** default to full PARA paths - they are noise. Relies on Obsidian shortest-unique resolution.
    - **A qualified link must be a real path suffix of the target file, not a folder path.** A folder note lives at `<Folder>/<Folder>.md`, so the path to it ends in the doubled segment: link to `Projects/Projects.md` as `[[Projects/Projects]]`, never `[[Projects]]` (that points at the *folder* and does not resolve - Obsidian silently falls back to bare-basename matching).
- **Grouping is encoded in the link path, not a separate field.** A curated sub-collection (e.g. the `Corpus/` collection) is expressed by path-qualified links (`[[Corpus/Task-System]]`); an agent buckets entries by their link's path segment. There is no `group:` key - the folder path *is* the grouping and cannot drift from a label.
- **Ephemeral folders get *only* a `folder` entry - never an individual `link` spotlight for a doc inside them.** This covers `Inbox/`, `Archive/`. No spotlighting a "currently active" doc (e.g. the in-flight plan) as its own `nav.contents` entry - that creates a dangling link a human must remember to retire at archive time, and the folder entry already routes the agent in. Durable, stable sub-collections like `Corpus/` are the contrast: each member gets its own `link` precisely because they do not churn. The discriminator is *permanence of the contents*, not the folder.
- **In-folder file selection needs no schema support.** Inside a `folder` entry's scope, the `YYYY-MM-DD-Type-Title` artifact name ([[Artifact-Storage]]) is the recency/selection heuristic - the date prefix doubles as the sort key.

## Standard-Folder Completeness

A folder note should account for every standard subfolder that physically exists under it. The linter (`validate-frontmatter.ps1`) compares on-disk subfolders against the note's entries and surfaces gaps, with a different resolution per folder kind:

- **Ephemeral folders (`Inbox`, `Archive`)** - get a single `folder:` entry. A missing one is **auto-addable**: the linter emits a ready-to-insert block using the house-style boilerplate below, and `vault-lint` inserts it (after the `link:` entries).

  | Folder    | `description`                                                  | `load_when`                                  |
  |-----------|----------------------------------------------------------------|----------------------------------------------|
  | `Inbox`   | Active working docs and in-flight content                      | working on in-progress tasks or finding a specific artifact |
  | `Archive` | Completed and inactive artifacts, date-prefixed                | researching prior artifacts or project history |

  The boilerplate is a sensible default - tune the wording to the note when it helps.
- **`Corpus/`** - a durable corpus of per-member `link` entries, **never** a single `folder:` entry. A member note the folder note does not reach by link is surfaced for **interactive** resolution (add a link or confirm it stays unlinked), not auto-added.

    **Reach is transitive through an intermediate folder note.** When a `Corpus/` subfolder has its own folder note, the parent links *that* note and the subfolder's members are routed to from it - the parent does not repeat them. A member counts as reached if the folder note links it directly, or links a folder note that (directly or transitively, cycles included) links it. Only a folder note is a valid hop: an ordinary member that cross-references a sibling in its own `nav.*` is prose, not routing, and confers no reach. Example: `Projects/Vault-MCP-Server/Vault-MCP-Server.md` links `[[Tools]]`, and `Corpus/Tools/Tools.md` routes on to the per-tool docs beside it.
- **Any other (non-standard) subfolder** - surfaced for interactive resolution; the user decides whether it warrants a `link`/`folder` entry or is intentionally omitted.

## Authoring Rules

- **No placeholders.** Omit a field rather than writing an empty one. (Supersedes the old `*No additional instructions.*` convention.)
- **No backslashes in double-quoted scalars.** In YAML a backslash is an escape character inside `"..."`, so a Windows path like `"C:\Repos\app"` is malformed (`\R` is an invalid escape) and a parser will drop or mangle it. Write such values with **forward slashes** (`"C:/Repos/app"`) or in **single quotes** (`'C:\Repos\app'`). `[[wikilinks]]` and repo-relative `folder:` paths already use forward slashes, so this only bites free-text values.
- **Skill-owned files carry a skill directive.** A file whose format is owned by a skill gets a `use_skill:` entry in `agent.instructions`, naming the condition (`when:`) under which agents must consult or route through that skill rather than act on the file unassisted. Most `vault-docs`-owned types are edit-only (`when: "editing this file"`); `Tasks.md` additionally gates on read, since its state markers and plugin fields need the skill's format knowledge to interpret correctly, not just to write safely. Authored from the template / by the skill at scaffold time, never hand-duplicated. Cases: every `Tasks.md` (`vault-tasks`); every doc type `vault-docs` owns - planning docs, corpus aspect docs, idea docs, chat captures, reading captures, and implement working files.

## Worked Examples

### Folder note (area) - `Areas/Personal/Personal.md`

```yaml
nav.contents:
  - link: "[[Personal/Tasks]]"
    description: "Task management belonging to this area"
    load_when: "working on tasks"
  - link: "[[Family]]"
    description: "Katie, Samantha, Nolah, parents, siblings"
    load_when: "family details needed"
  - link: "[[Medical]]"
    description: "Visit log, weight loss (tirzepatide), dermatology"
    load_when: "medical details needed"
```

`Family` and `Medical` carry their own intrinsic sensitivity rules as `pinned:` entries in `agent.instructions` on those leaf notes (instruction locality), not on the folder note.

### Folder note with a Corpus collection and folder entries - `Areas/Vault-Dev/Vault-Dev.md`

```yaml
nav.contents:
  - link: "[[Vault-Dev/Tasks]]"
    description: "Task management belonging to this area"
    load_when: "working on tasks"
  - link: "[[Corpus/Task-System]]"
    description: "Per-context Tasks.md model, states, item format, and the vault-tasks skill"
    load_when: "task-system design needed"
  - folder: "Areas/Vault-Dev/Inbox"
    description: "Active working set - planning docs, idea docs, and other in-flight content"
    load_when: "looking for or working on an in-flight plan or idea"
  - folder: "Areas/Vault-Dev/Archive"
    description: "Completed/frozen plans and ideas, date-prefixed"
    load_when: "researching historical vault-design decisions"
```

The `Corpus/` members are individual path-qualified links (durable corpus); the ephemeral `Inbox/`/`Archive/` folders are single `folder` entries.

### Leaf note with an intrinsic policy

```yaml
agent.instructions:
  - pinned: "This note holds sensitive medical and insurance identifiers; never include its contents in an email or any outbound message."
```

### Skill-owned file

```yaml
agent.instructions:
  - use_skill: "vault-docs"
    when: "editing this file"
```

## Deferred (reserved, not yet implemented)

- **`graph.*`** - a machine-maintained structural layer (forward links, entities). When built it begins as provisional `graph.*` frontmatter, kept clean so a later export to a sidecar store is a one-line prefix filter. Owned by a future watcher/dreamer. See [[Idea-Vault-Watcher-Dreamer]] and [[Idea-Sidecar-Graph-Store]].
- **`id`** - a rename-stable per-note join key, generated only once a sidecar/watcher/dreamer needs it. Generation scheme and field name (`id` vs `uid`) are open.
