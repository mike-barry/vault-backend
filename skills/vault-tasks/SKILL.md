---
name: vault-tasks
description: Add, update, and prune tasks across the vault's distributed Tasks.md files. Use when the user says "add a task", "new task", "capture this as a task", "update the task", "mark X done", "what am I working on", "task for project X", "prune done tasks", "clear completed", "add a reminder", "remind me", or otherwise wants to record, change, or clean up a todo. Also covers initializing a missing Tasks.md for a single project or area ("init task files").
---

# Vault Tasks

Manages the vault's distributed task lists. Tasks live in per-project and per-area `Tasks.md` files — one per Area and one per active project — not in a single global list. This skill owns adding tasks, updating them, routing new tasks to the right file, pruning completed ones, and backfilling missing task files.

For tasks that outgrow a list item, hand off to the `vault-docs` skill (see [[#Spinning Out to an Artifact Doc]]).

## Sections

Every `Tasks.md` uses these sections, in this order. Omit a section only if the file never needs it; prefer keeping them present and empty.

| Section | Meaning |
|---------|---------|
| `🔔 Reminders` | Lightweight, checklist-free notes: things to remember, time-anchored cues, or quick errands. Not tasks — no checkbox, no lifecycle, no plugin fields. |
| `🔥 Active` | Currently being worked on, or next-up and prioritized. Tasks may be `[ ]` (queued) or `[/]` (actively in progress). |
| `🧱 Blocked` | Blocked on someone or something external. Tasks may be `[ ]` or `[/]`. Note what is being waited on. |
| `📋 Backlog` | Intend to act on eventually; not prioritized or started. Always `[ ]`. |
| `🗺️ Side Quests` | Passive musings or curiosities; may never be acted on, no obligation. Always `[ ]`. |
| `✅ Done` | Completed (`[x]`) or cancelled (`[-]`). Kept as a short recently-completed trail, pruned periodically. |

`Backlog` carries intent to act; `Side Quests` is exploratory with no obligation. Keep them distinct.

## Reminder Format

Reminders are plain bullets — no checkbox, no plugin fields, no lifecycle. Use `@time` to anchor time-sensitive items:

```
- Buy dog food
- Project meeting @10am
- Follow up with Alex after standup
```

Remove a reminder by deleting its line when the user says it's done or no longer needed. There is no "done" state — reminders are either present or gone.

## Task Format

Three tiers — use the lightest one that fits. Every task ends with one or more emoji fields from the Obsidian Tasks plugin. The created date (`➕`) is always present. Other fields are added only when applicable.

**Tasks plugin fields** (place in this order, after all freeform text):

| Field | Emoji | When to use |
|-------|-------|-------------|
| Priority | 🔺 ⏫ 🔼 🔽 ⏬ | Only when user specifies. Levels highest→lowest: 🔺 highest, ⏫ high, 🔼 medium, 🔽 low, ⏬ lowest. Omit for normal/unspecified priority. |
| Start date | 🛫 YYYY-MM-DD | Only when user specifies a start date |
| Scheduled date | ⏳ YYYY-MM-DD | Only when user specifies a scheduled date |
| Due date | 📅 YYYY-MM-DD | Only when user specifies a due date |
| Created date | ➕ YYYY-MM-DD | Always — set to today when adding the task |
| Done date | ✅ YYYY-MM-DD | Set to today when completing the task |
| Cancelled date | ❌ YYYY-MM-DD | Set to today when cancelling the task |

**Simple** — straightforward tasks with no metadata:
```
- [ ] Short description | ➕ 2026-06-19
```

**Medium** — needs freeform context and/or metadata. The freeform trail uses ` | ` (pipe) as a separator; the text always ends with a final ` | ` so Tasks plugin fields follow cleanly:
```
- [ ] **Task title** - context | for-whom | 📅 2026-06-30 ➕ 2026-06-19
```

**Detailed** — needs steps, links, or sub-tasks. Use **as many sub-bullets as needed**:
```
- [ ] **Task title** - context | for-whom | 📅 2026-06-30 ➕ 2026-06-19
    - Sub-bullet for detail
    - Another sub-bullet — links, steps, or sub-tasks
```

**Done** — completed item in the `Done` section. No strikethrough. Keep only the `➕` created date and the `✅` done date (or `❌` cancelled date) after a single `|`; drop all other plugin fields and freeform text:
```
- [x] Task title | ➕ 2026-06-19 ✅ 2026-06-25
```

## Add a Reminder

1. **Route it** using the same routing tree as tasks (active project first, then Area).
2. **Place it** in the `Reminders` section as a plain bullet — no checkbox, no plugin fields.
3. Use `@time` if the user specifies a time (e.g. `@10am`, `@end of day`).

## Add a Task

1. **Route it** to the correct `Tasks.md` using the routing tree below.
2. **Place it** in the right state section — usually `Active` if it's being worked on now, otherwise `Backlog`. Use `Blocked` if it's blocked, `Side Quests` if it's a no-obligation curiosity.
3. **Check for subsections** — After choosing a state section, read the target `Tasks.md` and look for `**bold heading**` lines (a line consisting only of `**text**`) inside that section. If any exist, use `AskUserQuestion` with the found subsection headings as options before writing. If none exist, place the task directly under the `##` section heading without asking.
4. **Format it** with the lightest item tier that fits. Always append `➕ YYYY-MM-DD` (today's date). Add priority, due, scheduled, or start fields only if the user specifies them.

### Routing Tree

1. Load `Projects/Projects.md`. Does the task clearly belong to an **active project** listed there? If so, add it to that project's `Tasks.md`.
2. Otherwise, which **Area** does it belong to? Load `Areas/Areas.md` to get the current list of areas. Add the task to the matching area's `Tasks.md`.
3. **Ambiguous?** Ask the user rather than guessing.

Every Area is assumed to have a `Tasks.md`. If one is missing, run the [[#Initialize Task Files|init action]].

## Update a Task

- **Change state** — Move the item to the appropriate section (e.g. `Backlog` → `Active` when work starts, or `Active` → `Blocked` when it becomes blocked). When moving to `Blocked`, record the blocker in the pipe-separated metadata trail (e.g., `| blocked on: Bob's review |`).
- **Promote to in-progress** — Set `[/]` on a task in `Active` when the agent is actively working on it with the user in the current session. The user manages this transition manually otherwise.
- **Edit detail** — Adjust the title or body in place; promote to a heavier item tier if it has grown.
- **Mark done** — Move the item to the `Done` section, set `[x]`, and append today's done date: `✅ YYYY-MM-DD`. Keep only the `➕` created date; drop all other plugin fields and freeform metadata. Do not delete the item; the `Done` trail is cleared by `prune`, not on completion.
- **Cancel** — Move the item to the `Done` section, set `[-]`, and append today's cancelled date: `❌ YYYY-MM-DD`. Keep only the `➕` created date; drop all other plugin fields and freeform metadata. Use for tasks deliberately abandoned, not merely deferred.
- **Spin out** — When the user requests a planning doc for a task, collapse the item to a single-line back-reference.

## Spinning Out to an Artifact Doc

When a task outgrows a list item, it spins out to an artifact doc. Two types, same task action:

- **Idea doc** (owned by `vault-docs`): exploration or research tasks where thinking is the output — triggered by words like "explore", "research", "brainstorm", "think about".
- **Planning doc** (owned by `vault-docs`): tasks needing upfront design decisions before implementation — triggered when the user explicitly asks to plan it out.

The task action is identical in both cases:

1. **Set the task to `[/]`** (in progress). Spinning out means active work is underway — the task is not merely queued.
2. **Collapse the list item** to a single-line back-reference. Add a brief context note before the link **when the title alone doesn't convey what the task is about**:
   ```
   - [/] **Short title** - <brief context> - See [[DocName]]. | ➕ 2026-06-19
   - [/] **Self-explanatory title** - See [[DocName]]. | ➕ 2026-06-19
   ```
   The optional context note lets a future agent judge from the list alone whether the task is relevant to the current conversation, and therefore whether to load the referenced doc. Keep it to a phrase — enough to signal applicability, not a summary.
3. **Hand off** to the appropriate skill to scaffold the artifact doc. It lives in an **`Inbox/`** of the same project or area as the `Tasks.md` that references it.

## Prune Done Tasks

Clears stale completed and cancelled items from the `Done` trail. Triggered on demand ("prune done tasks", "clear completed").

1. Scope to the file in context by default, or all task files if asked ("prune all done tasks"). If no file is clear from context, ask the user to specify.
2. Find `Done` items — both `[x]` (completed, with `✅ YYYY-MM-DD`) and `[-]` (cancelled, with `❌ YYYY-MM-DD`) — whose date field is **older than 7 days** from today. (Use a different cutoff if the user specifies one, e.g. "prune anything older than 30 days".)
3. **List the matching items and confirm with the user before deleting.**
4. On confirmation, remove them, leaving the empty `Done` heading in place. Report how many were pruned from which files.

## Initialize Task Files

Creates a `Tasks.md` for a single project or area folder. Load `init.md` (same skill directory) for the full instructions — it covers what to ask the user and how to run the scaffold script.
