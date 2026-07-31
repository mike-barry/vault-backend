# Planning Doc Flow

Owns the **planning doc** artifact: a decision record capturing the *why* and the *journey* of work that needs upfront design, whether spun out of a task or started ad hoc in conversation. It is **not** mutated into a corpus doc at close-out — it freezes there as a permanent record of how the decisions were reached, while the current *what/how* lives separately in corpus docs (owned by the corpus flow).

This flow has four sub-flows: **scaffold** a new planning doc, **maintain** an active one, **start implementation** on a finalized one (handing off to `implement-doc.md` or `implement-inline.md`), and **close out** a finished one. It pairs with `vault-tasks` (which collapses the originating task to a back-reference) and the `corpus.md` flow (which the close-out hands off to).

## Planning Doc Shape

Every planning doc uses these sections, in this order.

| Section | Purpose |
|---------|---------|
| Frontmatter | `doc.created` + `doc.type: Plan` — schema per [[Document-Conventions]] — plus an `agent.instructions` `use_skill:` entry routing edits through this skill, per [[#Scaffold a Planning Doc]]. |
| Intro paragraph | One short paragraph under the H1: what this plans, the task it serves if one exists (link the `Tasks.md` item), and current status. No heading. |
| `## Goals` | What the work is trying to achieve. The motivation, not the steps. |
| `## Locked Decisions` | A **terse log of closed forks** — one entry per settled decision: the claim, and the alternative that was rejected with why it lost. Grouped under the Design subsection each belongs to. See [[#What Earns a Locked Decision]]. |
| `## Design Sections` | The substance of the plan — target design, broken into H3 subsections as needed. **This is the sole source of truth for the current what/how.** Section title can be specific (e.g. `## Target Design`). |
| `## Open Questions` | Only the decisions that are *genuinely still open*. When one resolves, it leaves this section — it is not kept here as a Resolved note. |
| `## Proposed Implementation Checklist` / `## Implementation Checklist` | Sequenced `- [ ]` steps. Titled with the "Proposed" qualifier from scaffold through the entire implementation phase, since most plans don't survive contact with implementation unchanged; retitled to `## Implementation Checklist` at collapse (full flow) or once inline implementation finishes (inline flow has no separate sync step), and left in place at close-out as a completed record — never stripped. |
| `## Out of Scope` | What this plan deliberately excludes, and where excluded work is tracked instead. |

H1 is a content-note title in Title Case (e.g. `# Example Plan`), per [[Document-Conventions]] — a planning doc is a content note, not a folder note, so it takes no `.md`-in-title. It does carry one intrinsic-policy `use_skill:` entry in `agent.instructions` (see [[#Scaffold a Planning Doc]]) routing its own edits through this skill; no other `agent.*`/`nav.*` frontmatter applies.

## Scaffold a Planning Doc

Triggered when a task needs upfront design (recognizing that is `vault-tasks`' job, which hands off here) or when the user asks directly to plan something out with no task behind it — the direct ask is itself the approval to proceed.

1. **Locate the project or area.** A planning doc lives in the **`Inbox/` subfolder** of the project or area it belongs to (e.g. `Areas/Vault-Dev/Inbox/`, `Projects/<Project>/Inbox/`), alongside the context's `Corpus/`. If an originating task exists, find the `Tasks.md` whose item is spawning this doc and use its context folder. Otherwise, determine the project or area from the conversation, asking the user if it is unclear.
2. **Name it** `Plan-<Description>.md` in `Title-Case-With-Hyphens` (e.g. `Inbox/Plan-Example.md`), descriptive enough to identify without opening.
3. **Create the doc** using the [[#Planning Doc Shape]]. Fill what is known from the conversation; leave `Open Questions` for what is not, and seed the `## Proposed Implementation Checklist` with the sequenced steps. Inject the skill-owned-file directive by running `scripts/add-skill-directive.ps1 -DocPath <path> -When 'editing this file or acting on its checklist'`.
4. **Collapse the originating task**, if one exists. Hand off to `vault-tasks` with the doc name — it owns the spin-out action and knows how to format the collapsed back-reference. If the doc has no originating task (an ad hoc plan started in conversation), skip this step.
5. **Cross-link.** If an originating task exists, link the planning doc back to its `Tasks.md` item in the intro paragraph. If an idea doc exists for this concept, load it and use it to seed the plan (Goals, Open Questions, initial design thinking), then link it in the intro paragraph — the idea doc is the upstream context, not a section to copy verbatim. Add wiki-links to any related notes.

## Maintain an Active Planning Doc

Triggered whenever an in-progress plan is updated as work proceeds. Keep it lean — it loads into context every session, so duplication costs directly.

**The one-source rule.** Design Sections carry the design; Locked Decisions carry the closed forks. Design describes the system that exists, never why it isn't something else — that is all the log adds, and an entry restating its subsection is dead weight.

**Making a decision.** Put the design detail in the relevant Design subsection, then add a Locked Decisions entry. Never paste the design body into the log.

`- **The toilet roll hangs over the top.** Rejected: hanging under, which makes the loose end hard to find.`

**Resolving an Open Question.** Fold the answer into Design Sections and delete the question. Add a Locked Decisions entry only if a fork closed — a question settled by a fact leaves nothing to log. Never keep a struck-through "Resolved" copy.

**Reversing a decision.** Rewrite the existing entry; never add a second one for the same fork. The new claim takes the entry, the superseded decision becomes its rejected alternative, and the reason names what flipped it. Update Design Sections to match.

`- **The toilet roll hangs under.** Rejected: hanging over the top, done that way until the cat learned to unspool it.`

### What Earns a Locked Decision

An entry needs a **real fork** — something rejected. Without one it is a design fact and belongs in Design Sections alone. Two exceptions:

- **Forced** — the alternative is not viable, but the reason is non-obvious enough that someone will propose it anyway. Record what makes it unavailable.
- **Sequencing** — nothing is contested, but acting late loses the option. Record the cost of not deciding.

Scope statements are not decisions: "X is not built" belongs in `## Out of Scope` alone.

**Order.** Entries group under the Design subsection they belong to, in the order those subsections appear, and run oldest first within a group. The group label is a wikilink to that subsection, so entries carry no individual pointer.

## Start Implementation

Triggered by an explicit user signal that they're ready to begin implementing a finalized plan (e.g. "let's implement this," "let's start," "let's get started") — never automatically just because Design settles and `Open Questions` empties out; a plan can sit finalized for a while before work begins.

1. **Verify readiness.** Confirm `Open Questions` is empty and Design Sections reflect the settled design. If anything is still open, stop and resolve it through the normal Maintain flow with the user — do not resolve it unilaterally as a side effect of starting implementation. Once confirmed, state plainly what's settled and get the user's explicit acknowledgement that the plan is complete and ready, before continuing.
2. **Propose the decision gate.** State whether this plan warrants isolating implementation churn in a separate file, with your reasoning — is implementation likely to touch the plan often enough that a second file earns its overhead? ("Is this plan simple" is harder to judge upfront, so don't reason from that framing.) Then get the user's **explicit approval** on which flow to use. Do not decide and hand off unilaterally.
3. **Hand off**, per the approved flow — full flow → `implement-doc.md`; inline flow → `implement-inline.md`.

## Close Out a Planning Doc

Triggered when the task's implementation is complete ("close out the planning doc", "freeze this plan", "archive this plan"). The planning doc is **frozen**, not rewritten. **A completed Implementation Checklist does not itself authorize this flow** — even found later, on its own, it still requires the user's explicit ask before archiving or corpus-reconciliation begins.

If the full flow was used, `implement-doc.md`'s collapse must have already run. If the inline flow was used, no separate step is needed — its edits already landed here.

1. **Confirm it's done.** Every `## Implementation Checklist` item should be checked (or explicitly moved to `Out of Scope`). If work remains, it is not ready to close out.
2. **Freeze the record.** Leave the checklist in place as a completed record, and resolve any remaining `Open Questions` the normal way (fold into Design Sections, log the decision, remove the question) so the section ends empty or nearly so. The preserved journey *is* the Locked Decisions log plus the completed checklist, captured leanly — close-out does not add a verbose narrative on top, and the one-source rule still holds.
3. **Move to the local archive.** Call `vault-doc-archive` with type `Plan` and the close-out date. It applies the naming convention, places the file in the project or area's local `Archive/` subfolder, and updates all wiki-link back-references.
4. **Reconcile the corpus.** Judge whether the completed work left durable facts worth ongoing reference. If so, hand off to the corpus flow to **update existing or add new corpus doc(s)** capturing the as-built *what/how*. **If you judge it does not — a one-off task with nothing durable to document — say briefly why it looks like a skip and confirm with the user before skipping**, since they may know of durable facts that aren't obvious from the work alone. (Corpus docs are living, per-aspect, and updated over time — they are not a frozen snapshot of this plan.)
