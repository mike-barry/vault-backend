# Implement Inline Flow

Owns implementing a finalized planning doc **in place**, with no second file. `plan.md`'s [[plan#Start Implementation]] sub-flow hands off here once the user approves this flow at the decision gate — the plan is unlikely to be touched often enough during implementation for a separate implement doc to earn its overhead. This flow is just as rigorous as `implement-doc.md` — the difference is where the churn lands, not how carefully it's handled.

This flow has three sub-flows: **setup**, **execute** steps against the plan directly, and **finish** by retitling the checklist.

## Setup

Triggered once `plan.md`'s Start Implementation approves this flow. There is nothing to scaffold — flag readiness and stop: report back, e.g. "Plan ready for inline implementation — ready to proceed?" — and wait. Do not begin Execute Steps until the user explicitly confirms.

## Execute Steps

Triggered only after the user's explicit go-ahead following Setup above — never assumed from the initial approval to use this flow.

1. **Proceed one step at a time**, or a user-requested batch of steps, only with explicit approval — never unprompted.
2. **Check off `## Proposed Implementation Checklist` items in place** as they complete, and freely reorder, add, or trim items as reality demands.
3. **Fold deviations directly into the plan as they're discovered** — no intermediate log. When a step surfaces a design change, put the detail in the relevant Design subsection and add a one-line Locked Decisions entry (claim, one-line why, date, pointer), per `plan.md`'s [[plan#Maintain an Active Planning Doc|Maintain]] one-source rule. Only genuine decision points worth remembering later get an entry — not routine progress or false starts.

## Finish

Triggered once every checklist item is done (or moved to `Out of Scope`).

1. **Retitle the checklist** from `## Proposed Implementation Checklist` to `## Implementation Checklist`. There is no separate sync step — the checklist and design edits already landed on the plan as work progressed, so this retitle is the entire "finish" action.
2. **Report that implementation is complete** and ask whether to proceed to `plan.md`'s [[plan#Close Out a Planning Doc|Close Out]] — do not continue into Close Out automatically.
