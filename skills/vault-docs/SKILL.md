---
name: vault-docs
description: >
  Front door for vault documents — creating, updating, and closing out the note types this
  vault uses. Routes to the right flow based on what the user wants to do.

  Invoke for:
  - **Planning docs** — "create a planning doc", "start a design plan", "plan this out",
    "spin this into a planning doc", "I need to plan X", "let's design this first",
    "close out the planning doc", "freeze this plan", "archive this plan",
    "let's implement this plan", "let's work on implementing it", "start implementing X",
    "work on the plan's checklist"
  - **Corpus docs** — "create a corpus doc", "document the design", "write the as-built doc",
  "assimilate", "assimilate this", "assimilate into the corpus",  "update the corpus", 
  "update the design", "reconcile the corpus", "reconcile the design", "document how X works",
  "capture the facts about X", "write up the current state"
  - **Idea docs** — "capture this idea", "create an idea doc", "jot down this idea",
    "let's capture this thinking", "save this as an idea", "start an idea thread"
  - **Chat captures** — "save this chat", "save this conversation", "save this as a note",
    "capture this conversation", "create a note from this"
  - **Reading captures** — user shares a URL and says "save this", "save this for later",
    "add this to my reading list", "save this article", or similar reading-bookmark intent

  Do NOT invoke for: renaming files (use vault-doc-rename), archiving files (use
  vault-doc-archive), frontmatter edits (use vault-agent-frontmatter), vault formatting issues
  (use vault-lint), or general questions about a document's content.
---

# vault-docs

Router for vault document flows. This skill confirms the doc type and loads the matching subskill.

## Doc-Type Registry

| Type | What it is | Where it lives | Flow file |
|------|-----------|----------------|-----------|
| **Planning doc** | Frozen decision record — the *why/journey* of a task or decision that needs upfront design. Scaffolded at the start, maintained as decisions land, archived at close-out. | `<Project-or-Area>/Inbox/` (`Plan-*.md`) | [plan.md](plan.md) |
| **Corpus doc** | Living as-built reference corpus — the authored, current-state *what/how* facts about a project's or area's subject, split into per-aspect docs updated over time. | `<Project-or-Area>/Corpus/` | [corpus.md](corpus.md) |
| **Idea doc** | Lightweight, obligation-free pre-commitment thinking thread. No lifecycle requirement. | `<Project-or-Area>/Inbox/` (`Idea-*.md`) | [idea.md](idea.md) |
| **Chat capture** | Structured note preserving a conversation — summary, decisions, action items, optional transcript. | `<Project-or-Area>/Inbox/` (`Chat-*.md`) | [capture-chat.md](capture-chat.md) |
| **Reading capture** | Saved article/URL with summary and key takeaways for later reading. | `Areas/Research/Inbox/` (`Reading-*.md`) | [capture-reading.md](capture-reading.md) |

**Always load [[Vault-Organization]] before creating any file** to confirm correct placement.

## When Not to Route

Stop immediately if:

- The user wants to **rename or move a file** → use `vault-doc-rename`
- The user wants to **archive a specific file** → use `vault-doc-archive`
- The user wants to **edit frontmatter** → use `vault-agent-frontmatter`
- The user wants to **fix formatting or lint issues** → use `vault-lint`
- The request is to **discuss, read, or answer a question about** an existing document's content → answer directly without invoking any flow
- The request does not map to any doc type in the registry above → respond normally

## Routing Steps

1. **Identify the doc type** from the user's request and the registry above. If ambiguous, use `AskUserQuestion` with the candidate types (from the registry) as options — do not guess or ask free-form.
2. **Load the matching flow file** from the registry and follow its steps completely.

## Scripts

- **`scripts/add-skill-directive.ps1`** — every flow's scaffold step calls this directly (no other skill invocation needed) to inject the fixed `use_skill: "vault-docs"` entry into a new doc's `agent.instructions`. A thin CLI wrapper fixed to `-UseSkill 'vault-docs'`; the actual logic (`Add-AgentInstructionEntry`) lives in `_shared/vault-frontmatter.ps1`, shared with every other authoring skill. Has its own `scripts/unit-tests.ps1`.
