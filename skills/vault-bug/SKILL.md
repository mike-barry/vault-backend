---
name: vault-bug
description: >
  Capture an observed instance of undesirable agent behavior, analyze its root cause against
  the vault's navigation/guidance layer, and produce a structured `Bug-` doc that doubles as
  an actionable improvement ticket. Use when the user flags something the agent just did
  wrong — "that's not right", "log this as a bug", "capture this failure", "why did you do
  that", "that should not have happened" — or explicitly invokes `vault-bug`.

  Do NOT invoke for: routine bug fixes in vault content, doc-type creation (use `vault-docs`),
  or retroactive scans of past sessions — this is a human-triggered, in-session capture only.
---

# Vault Bug

Captures an in-session observation of bad agent behavior, reasons through *why* it happened using a two-dimensional root-cause taxonomy, and writes a `Bug-` doc that is both the incident record and the improvement ticket.

## The `Bug-` Doc Type

An Inbox file type alongside `Plan-`, `Idea-`, etc. Always date-suffixed — the incident date is meaningful, per [[Document-Conventions]]'s Inbox filename rule.

**Location:** `<Project-or-Area>/Inbox/`, using the same context-resolution as other Inbox docs — determine the project or area from the conversation (where did the bad behavior happen?). If it's unclear, use `AskUserQuestion` with the plausible candidate projects/areas as options (defaulting `Vault-Dev` in the list, since that's where most vault-guidance issues surface). Most failures will land in `Areas/Vault-Dev/Inbox/` since that's where vault-guidance issues surface, but a failure specific to another project's domain content belongs there instead.

**Filename:** `Bug-<Description>-YYYY-MM-DD.md`, `Title-Case-With-Hyphens`, dated today.

**Frontmatter:** `doc.created` (today) + `doc.type: Bug` — schema per [[Document-Conventions]].

**H1:** Title Case description of the incident, no `Bug-` prefix and no `.md` — it is a content note, per [[Document-Conventions]] (e.g. `# WIP Doc Routed to Corpus`, not `# Bug - WIP Doc Routed to Corpus`).

### Shape

| Section | Purpose |
|---------|---------|
| Intro paragraph | One or two sentences: what happened and when. No heading. |
| `## Observed Behavior` | What the agent did — verbatim quotes where useful, paraphrase otherwise. Enough detail to reconstruct the incident without the original transcript. |
| `## Expected Behavior` | What should have happened instead, and why that's correct. |
| `## Root Cause` | A **Type:** line naming the root cause (see taxonomy below), then prose walking through *why* the gap let the behavior happen — trace the actual reasoning chain, not a guess. Ends with a **Fix targets:** line naming which artifact(s) should change. |
| `## Proposed Fix` | Concrete, numbered changes to make — specific enough to act on directly (what to add, where, and the resulting behavior change). |
| `## Status` | `- [ ] Fix implemented` checkbox. Add a link to the implementing commit/PR/doc once done. |

### Root Cause Taxonomy

Two independent dimensions. A single failure can involve both, or land on just one.

**Root cause type** (the why):

| Type | Description |
|------|-------------|
| Missing context | The agent needed a note or section but didn't load it — an instruction existed (or should have) to trigger that load but didn't fire or wasn't there. |
| Missing breadcrumb | No pointer existed at all — a `nav.contents` entry, `load_when` condition, skill step, or cross-reference that would have routed the agent simply wasn't there. |

**Fix target** (where the fix lives):

| Target | Lives in |
|--------|---------|
| Guide doc | `Vault-Guide.md`, `Document-Conventions.md`, `Vault-Organization.md`, any `*-Guide.md` |
| Skill file | `.claude/skills/<skill>/` |
| Folder routing | Folder note `nav.*` frontmatter |

Memory is deliberately excluded as a fix target — it isn't part of the vault's guidance layer.

## Flow

1. **Trigger.** Invoked directly, or when the user flags something the agent just did as wrong. Accept an optional description as args.

2. **Capture.** If the args (or surrounding conversation) don't already establish both what happened and what should have happened, ask:
   - What did the agent do?
   - What should it have done instead?

   Prefer pulling this from the conversation already in context over asking — the incident likely just happened in this same session.

3. **Analyze.** Reason through root cause using the [[#Root Cause Taxonomy|taxonomy]]:
   - Was there an instruction or trigger that *should* have loaded the right context, but didn't fire? → missing context.
   - Did no pointer exist at all to route the agent there? → missing breadcrumb.
   - Trace the actual chain: what did the agent load, in what order, and where did it diverge from the path that would have caught this. Name the specific fix target(s) — don't leave this vague.

4. **Draft.** Fill every section of the [[#Shape]] using the incident detail and the analysis above. Do not leave `Root Cause` or `Proposed Fix` generic — both should be specific enough that someone unfamiliar with this conversation could act on them.

5. **Locate and write.** Resolve the project or area per [[#The `Bug-` Doc Type|Location]] above, name the file, and write it. Report the path back to the user.

6. **Offer to implement.** Ask whether Mike wants the proposed fix applied now. If yes, apply it directly (edit the named guide doc, skill file, or folder note frontmatter — using `vault-agent-frontmatter` for any `nav.*`/`agent.*` change), then check `- [x] Fix implemented` and note what changed. If no, leave the doc as an open ticket.
