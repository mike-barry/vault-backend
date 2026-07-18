# Create Flow

Triggered by: "create a new mode", "add a mode for X", "new mode called X"

## Mode File Layout

Mode files follow the template in [mode.md](../mode.md), with `doc.created` + `doc.type: Mode` frontmatter (schema per [[Document-Conventions]]; `Mode` is never archived, so it's not in `vault-doc-archive`'s enum). Four optional sections in order — omit any section that has no content:

| Section | Purpose | Preamble |
|---|---|---|
| **Personality** | Voice and tone | "Adopt the following personality for this session. Maintain it consistently across all responses." |
| **Instructions** | Behavioral directives | "Follow these instructions for this session." |
| **Context** | Background facts, navigation pointers, stable reference | none |
| **Priorities** | Current-state snapshot: active projects, top-of-mind concerns | none |

Subsections (`###`) under Instructions are optional — use them when directives span distinct topics; write flat bullets for a single logical group.

Do not restate content that lives in corpus docs — point to the corpus instead. Avoid transient state (task lists, in-progress items) that will go stale.

## Steps

1. Confirm the mode name and a one-line description with the user.
2. Gather content for each section — ask the user what to include, or draft based on context and confirm. Omit any section the user leaves empty.
3. Render [mode.md](../mode.md): substitute `{{NAME}}`, `{{FRAMING_SENTENCE}}`, and `{{DATE}}` (today's date — `doc.type: Mode` is already literal in the template); fill each section with the confirmed content and its preamble line; drop empty sections entirely (do not leave blank `##` headings).
4. Write the file to `Resources/Vault/Modes/Mode-<Name>.md`.
5. Add a row to the inventory table in `Modes.md`.
6. Add a `nav.contents` entry to `Modes.md` frontmatter.
7. Confirm the new mode with the user.
