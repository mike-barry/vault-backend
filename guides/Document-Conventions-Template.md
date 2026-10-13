---
doc.created: 2026-05-31
---
# Document-Conventions.md - Vault Document Conventions

Rules for creating and editing documents in this vault.

## Agent Instructions

When creating or significantly modifying any note:

- Apply the heading, length, filename, dash, and wiki-link rules defined in this document
- These rules must hold for the text you actually write, not just be satisfied by having read this doc earlier in the session — re-check against the rule at the point of writing, especially in long multi-file sessions. An existing file's current formatting (including a file you're using as a style or structural reference) is not a valid substitute for checking the written rule, since existing content may itself predate or violate it.
- For creating or managing planning docs, corpus docs, idea docs, chat captures, and reading captures, use the `vault-docs` skill
- For frontmatter rules (`nav.*` / `agent.*`) and when to apply them, see the `vault-agent-frontmatter` skill
- Flag any existing violations you notice rather than silently fixing them outside the scope of the current task

## Headings

All notes begin with an H1 title in Title Case. All headings use Title Case. No trailing punctuation; one blank line before and after each heading.

After the H1, body sections use H2 for top-level sections and H3 for subsections. Avoid going deeper than H3 - if you need more structure, use bold text or nested lists instead. Never skip a level.

Short notes that don't need sections should have only the H1.

### Content Notes

H1 is the note title:

```
# My Note Title
```

### Guide and Folder Notes

H1 uses the filename-plus-description format:

```
# Filename.md - Short Description of Purpose
```

The `.md` in the title is intentional - it marks this as a structural file rather than a content note.

## Lists

Use 4 spaces per nesting level for nested list items. This applies to both plain bullets and task checkboxes (`- [ ]`).

```
- Top-level item
    - First nested level (4 spaces)
        - Second nested level (8 spaces)
```

Obsidian's Tasks plugin requires 4-space indentation to recognize a nested item as a sub-task; 2-space indentation is not rendered correctly.

## Length

Match a document's length to its substance. Cover what the task needs, then stop - no padding with filler sections, redundant summaries, restated context, or boilerplate. A doc that repeats its own content in a closing summary is too long by that summary.

Brevity is measured against what a cold reader needs, not against what is obvious right now. This matters most for corpus docs, which are maintained reference read fresh in later sessions. Context that feels redundant while writing is often load-bearing on the next read. Keep it when a reader without the current conversation would need it; cut it when it only restates what the doc already says.

## Filenames

- Use `Title-Case-With-Hyphens` for multi-word filenames (e.g. `Example-Note.md`).
- Hyphens separate words; do not use spaces or underscores.
- Keep names concise but descriptive enough to identify the note without opening it.

### Inbox Filenames

Files in the root, project, or area's `Inbox/` subfolder use the `Type-Description[-YYYY-MM-DD].md` convention:

- Lead with a type prefix drawn from the standard vocabulary: `Plan-`, `Idea-`, `Reading-`, `Chat-`, `Meeting-`, `Research-`, `Note-`. The list is open-ended — any `TypeName-` prefix is valid.
- Append a trailing date when the date is meaningful: `Type-Description-YYYY-MM-DD.md`. Meetings and chats always get a date.
- The one exception to the leading-prefix pattern is the `-Implement` suffix on a planning doc's disposable working file (`Plan-<Description>-Implement.md`) — a suffix modifier rather than a type prefix, since it names a temporary artifact of an existing plan rather than a new doc type. See the `vault-docs` skill's `implement-doc.md` for its shape and lifecycle.

Examples: `Plan-Auth-Redesign.md`, `Reading-RAG-Mistakes-In-Production.md`, `Meeting-Project-Kickoff-2026-06-28.md`

## Provenance Frontmatter

Every authored document carries these frontmatter fields. Structural files (folder notes, Guide docs, skill-owned formats like `Tasks.md`) are exempt; see `vault-lint`'s provenance check for the full exclusion list.

| Field | Value |
|-------|-------|
| `doc.created` | `YYYY-MM-DD` — the document's capture date |
| `doc.archived` | `YYYY-MM-DD` — the date the file arrived in `Archive/` |
| `doc.type` | Title-Case single word from `vault-doc-archive`'s Known-Types table |

## Dashes

Use standard hyphens (`-`, U+002D) for all dashes in note content. When adding or modifying documents, replace any of the following characters with a standard hyphen.

| Character | Unicode | Name |
|-----------|---------|------|
| – | U+2013 | En dash |
| — | U+2014 | Em dash |
| ― | U+2015 | Horizontal bar |
| ‒ | U+2012 | Figure dash |

## Line Wrapping

Never hard-wrap prose with manual line breaks. Write each paragraph, bullet, and sentence as one continuous line.

## Wiki-links

- Cross-reference other notes using wiki-link syntax: `[[Note-Name]]` (filename without extension, no path).
- Add wiki-links whenever a note references a person, topic, or document that has its own note.
- Body links default to the bare `[[Note-Name]]` form above. May be path-qualified (`[[Corpus/Task-System]]`) when the path encodes additional meaning or disambiguates.

## Internal Heading Links

Obsidian does not resolve markdown-style fragment links (`[Section Name](#section-name)`, GitHub/CommonMark convention) - it only jumps to a heading through wikilink syntax. Use:

- `[[#Heading Name]]` - link to a heading in the same note.
- `[[Note-Name#Heading Name]]` - link to a heading in another note.
- `[[Note-Name#Heading Name|display text]]` - either form with custom display text.

Heading text is matched verbatim (case and spacing as written), not slugified.


