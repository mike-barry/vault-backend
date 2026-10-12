---
nav.contents: []
---
# Modes.md - Session Context Modes

Mode files for the `vault-mode` skill. Each mode is a self-contained context block - background facts, priorities, and framing injected into the session on demand.

## Available Modes

| Mode | File | Description |
|---|---|---|

## Adding a New Mode

Use the `vault-mode` skill - it renders the template, writes the file, and updates this inventory automatically.

To add manually: create `Mode-<Name>.md` using the layout below, add a row to the table above, and add a `nav.contents` entry to this file's frontmatter.

### Mode File Layout

Four optional sections in order - omit any that have no content:

| Section | Purpose |
|---|---|
| **Personality** | Voice and tone for the session; opens with the standard preamble |
| **Instructions** | Behavioral directives; opens with the standard preamble; use `###` subsections when directives span distinct topics |
| **Context** | Background facts, navigation pointers, stable reference |
| **Priorities** | Current-state snapshot: active projects, top-of-mind concerns |

Avoid restating content that lives in corpus docs - point to the corpus instead. Avoid transient state (task lists, in-progress status) that will go stale.
