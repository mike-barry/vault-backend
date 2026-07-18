# Implement Doc Flow

Owns the **implement doc** artifact: a disposable working file that isolates implementation churn from a finalized planning doc while work is in flight. It is not a new archived doc type — it has no independent permanence and is deleted (not archived) once collapsed back into the plan. It carries one frontmatter entry, the same skill-owned-file routing directive as every other `vault-docs` artifact, injected via `scripts/add-skill-directive.ps1 -DocPath <path> -When 'editing this file or acting on its checklist'` — the broadened `when:` shared with planning docs (see [[plan#Planning Doc Shape]]).
`plan.md`'s [[plan#Start Implementation]] sub-flow hands off here once the user approves this flow at the decision gate — the plan's implementation is likely to touch it often enough that isolating the churn in a second file earns its overhead.

This flow has three sub-flows: **scaffold** the implement doc, **execute** steps interactively, and **collapse** it back into the plan at the end.

## Implement Doc Shape

An implement doc is intentionally minimal — it borrows the plan's context by reference rather than restating Goals, Locked Decisions, or Design Sections.

| Section | Purpose |
|---------|---------|
| Intro paragraph | One line, back-link to the plan (`[[Plan-Description]]`). No heading. |
| `## Checklist` | Working copy of the plan's `## Proposed Implementation Checklist`. Freely checked off, reordered, added to, or trimmed as implementation reality demands. |
| `## Log` | Dated `### YYYY-MM-DD` entries for *novel* information only — deviations, discoveries, decisions, verification results. Not a step-completion narration; the checklist already shows that. |

Filename: `Plan-<Description>-Implement.md`, in the same `Inbox/` folder as the parent plan.

## Scaffold the Implement Doc

Triggered immediately once `plan.md`'s Start Implementation approves this flow.

1. **Create the doc** at `Plan-<Description>-Implement.md`, alongside the parent plan, with the `agent.instructions` directive described above. Write the intro back-link, then copy the plan's `## Proposed Implementation Checklist` items into `## Checklist` verbatim as the starting point. Open an empty `## Log`.
2. **Add the plan's forward link.** Edit the parent plan's intro paragraph to add a forward link to the new implement doc, alongside any existing back-link to an originating idea or task.
3. **This is the last edit the plan doc receives** until collapse. From here, every deviation, discovery, or decision goes in the implement doc's `## Log`, never back into the plan — see [[#Execute Steps]].
4. **Stop and report.** Once the doc is created and linked, report back — e.g. "Implement doc created at `Plan-<Description>-Implement.md` — ready to proceed?" — and wait. Do not begin Execute Steps until the user explicitly confirms.

## Execute Steps

Triggered only after the user's explicit go-ahead following the Scaffold checkpoint above — never assumed from the initial approval to use this flow. If you are arriving here but have not yet loaded the originating planning doc, do so now before proceeding with execution.

1. **Proceed one step at a time**, or a user-requested batch of steps, only with explicit approval — never unprompted. Check off `## Checklist` items as they complete, and freely reorder, add, or trim items as reality demands.
2. **Log novel information only.** When a step surfaces a deviation from the plan, a discovery, a decision, or a verification result, add a dated `### YYYY-MM-DD` entry (or append to today's) in `## Log` describing it. Do not narrate routine step completion — the checklist already shows that.
3. **Never edit the parent plan.** If something looks like it should change the plan's Design Sections or Locked Decisions, it goes in the Log instead; collapse is where that gets folded back in.

## Collapse the Implement Doc

Triggered once every `## Checklist` item is done (or moved to `Out of Scope`) and the user agrees to close out the implement doc. Proceed only with explicit user permission.

1. **Replace the plan's `## Proposed Implementation Checklist`** with the implement doc's final `## Checklist` state, retitled `## Implementation Checklist`.
2. **Distill the `## Log` into the plan as target-state, not history.** Fold design changes directly into the relevant Design Sections — write as if it had always been the design, not a "tried X, switched to Y" narrative. Add a terse Locked Decisions entry (claim, one-line why, date, pointer) only for genuine decision points worth remembering later, not routine progress or false starts.
3. **Remove the forward link** to the implement doc from the plan's intro paragraph.
4. **Report back** what was updated, then offer to delete the implement doc.
5. **On confirmation, delete the implement doc file** — a plain file delete, not `git rm` or `vault-doc-archive`. The file may never have been committed, so no git-specific instruction should be assumed.

After collapse, report that implementation is complete and ask whether to proceed to `plan.md`'s [[plan#Close Out a Planning Doc|Close Out]] — do not continue into Close Out automatically.
