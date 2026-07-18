---
name: vault-mode
description: >
  Load, list, create, or update session context modes. Modes inject background facts,
  behavioral instructions, and framing into the current session or a newly spawned one.

  Invoke for:
  - **Load** — "load work mode", "switch to vault-dev mode", "put me in HAL mode",
    "load work mode in a new session", "spawn a session in vault-dev mode"
  - **List** — "what modes are available", "list modes", "show me the modes"
  - **Create** — "create a new mode", "add a mode for X", "new mode called X"
  - **Update** — "add this as an instruction to X mode", "update the X mode to",
    "add X to the Y mode", "remove X from the Y mode"
---

# vault-mode

Manages session context modes stored in `Resources/Vault/Modes/`.

## Mode File Layout

Mode files follow the template in [mode.md](mode.md), with `doc.created` + `doc.type: Mode` frontmatter (schema per [[Document-Conventions]]; `Mode` is never archived, so it's not in `vault-doc-archive`'s enum). Four optional sections in order — omit any section that has no content:

| Section | Purpose | Preamble |
|---|---|---|
| **Personality** | Voice and tone | "Adopt the following personality for this session. Maintain it consistently across all responses." |
| **Instructions** | Behavioral directives | "Follow these instructions for this session." |
| **Context** | Background facts, navigation pointers, stable reference | none |
| **Priorities** | Current-state snapshot: active projects, top-of-mind concerns | none |

Subsections (`###`) under Instructions are optional — use them when directives span distinct topics; write flat bullets for a single logical group.

Do not restate content that lives in corpus docs — point to the corpus instead. Avoid transient state (task lists, in-progress items) that will go stale.

## Flows

### Load Flow

Triggered by: "load X mode", "switch to X mode", "put me in X mode"

1. Read `Resources/Vault/Modes/Modes.md` to get the inventory.
2. Match the requested name against available modes — exact first, then fuzzy/substring.
3. If multiple candidates match: use `AskUserQuestion` with the matching mode names as options.
4. If no match: use `AskUserQuestion` to offer either creating a new mode or naming a different one from the inventory shown.
5. **New session branch** — if the user asked to open a new session with this mode (e.g. "load X mode in a new session", "spawn a session in X mode"): resolve the mode file's absolute path and delegate to `spawn-session` with `--append-system-prompt-file <abs-path>`. Multiple modes: one flag per mode, personality modes before context modes.
6. **In-session branch** (default) — read the mode file and inject its full contents into the current session as a user message.

### List Flow

Triggered by: "what modes are available", "list modes", "show me the modes"

1. Read `Resources/Vault/Modes/Modes.md`.
2. Return the inventory table with mode names and descriptions.

### Create Flow

Triggered by: "create a new mode", "add a mode for X", "new mode called X"

1. Confirm the mode name and a one-line description with the user.
2. Gather content for each section — ask the user what to include, or draft based on context and confirm. Omit any section the user leaves empty.
3. Render [mode.md](mode.md): substitute `{{NAME}}`, `{{FRAMING_SENTENCE}}`, and `{{DATE}}` (today's date — `doc.type: Mode` is already literal in the template); fill each section with the confirmed content and its preamble line; drop empty sections entirely (do not leave blank `##` headings).
4. Write the file to `Resources/Vault/Modes/Mode-<Name>.md`.
5. Add a row to the inventory table in `Modes.md`.
6. Add a `nav.contents` entry to `Modes.md` frontmatter.
7. Confirm the new mode with the user.

### Update Flow

Triggered by: "add this as an instruction to X mode", "update the X mode to", "add X to the Y mode", "remove X from the Y mode"

1. Resolve the target mode via the same fuzzy matching as the load flow.
2. Read the current mode file.
3. Apply the change:
   - **Add content** — insert into the appropriate section; create the section (with preamble if applicable) if it doesn't exist yet.
   - **Edit content** — locate and revise the relevant line or block.
   - **Remove content** — delete the line or block; if the section is now empty, remove the section heading too.
4. Write the updated file.
5. If the change affects the mode's description, update the `Modes.md` inventory table and `nav.contents` entry.
6. Confirm the change with the user.
