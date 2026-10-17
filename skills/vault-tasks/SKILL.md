---
name: vault-tasks
description: Add, update, and prune tasks across the vault's distributed Tasks.md files. Use when the user says "add a task", "new task", "capture this as a task", "update the task", "start X", "mark X done", "finish X", "cancel X", "X is blocked", "move X to sprint", "move X to backlog", "what am I working on", "task for project X", "promote this task", "make a task doc", "tag this for the X list", "create a view", "show tasks for X", "check task files", "backfill task IDs", "prune done tasks", "clear completed", "add a reminder", "remind me", or otherwise wants to record, change, group, or clean up a todo. Also covers initializing a missing Tasks.md for a single project or area ("init task files").
---

# Vault Tasks

A task is one checkbox line in the `Tasks.md` of the project or area it belongs to, carrying a numeric ID. Its section heading is its queue and its checkbox symbol is its status. A task that outgrows its line gets an optional `Task-N` doc, and every cross-context view is a query over lines, never a copy of them. The full description, including line grammar and the task object fields, is [[Task-System]].

## Sections

| Section | Queue |
|---------|-------|
| `Reminders` | Plain bullets, no checkbox or lifecycle; `@time` anchors a time-sensitive one. |
| `Sprint` | Pulled from the backlog and committed, started or not. |
| `Blocked` | Waiting on someone or something external; the line's text says what. |
| `Backlog` | Intended eventually, not committed. |
| `Side Quests` | Curiosities with no obligation to act. |
| `Done` | Done or cancelled; a short trail pruned after 7 days by default. |

Status symbols: `[ ]` todo, `[/]` in progress, `[x]` done, `[-]` cancelled. Status is independent of queue, so a started task moved back to Backlog keeps its `[/]`; the only rule is that Done holds only `[x]` and `[-]`, and only Done holds them.

## Running the Script

Every verb is one call:

```
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-tasks/scripts/tasks.ps1 -Action <verb> ...
```

- **Arrays** are passed as one delimited string: `-Tags`, `-Tag`, `-AddTag`, `-RemoveTag`, `-Section`, `-Status`, `-Id` are comma-separated (`-Tags "list/weekend-2026-10-17,errand"`); `-Children` and `-AddChild` are newline-separated (in Bash, `-Children $'First\nSecond'`). Tags may be given with or without `#`.
- **Values** are case-insensitive. Sections: `Sprint`, `Blocked`, `Backlog`, `SideQuests`, `Done`, `Reminders`. Statuses: `todo`, `in-progress`. Priorities: `highest`, `high`, `medium`, `low`, `lowest`, `none`. Dates are `yyyy-MM-dd`, or `none` to clear.
- **Output** is one JSON document on stdout. Summarize it for the user; never paste raw JSON.
- **Errors** exit 1 with the explanation on stderr. Relay it verbatim and stop; never fall back to editing the file by hand.
- **Address tasks by ID**, found with `list` when the user names a task by its words.

## Routing a New Task

In this vault, load `Projects/Projects.md` and route to the `Tasks.md` of the active project the task clearly belongs to; otherwise load `Areas/Areas.md` and route to the matching area. Ask when ambiguous. If the target `Tasks.md` is missing, run [[#Init]].

## Verbs

### List

"What am I working on", "show tasks for X":

```
-Action list [-Path <file|folder>] [-Section Sprint,Blocked] [-Status todo,in-progress] [-Tag list/<name>] [-Id 17,18]
```

Default scope is the whole repo. Lines with a null `Id` are hand-written and not yet stamped; they are still real tasks.

### Add

```
-Action add -Path <Tasks.md|folder> -Title "<title>" [-Text "<context>"] [-Section <name>] [-Status in-progress] [-Tags ...] [-Priority ...] [-Start|-Scheduled|-Due <date>] [-Children ...]
```

- Section defaults to `Backlog`; use `Sprint` when the user says now or next, `Blocked` or `SideQuests` when that fits.
- Pass priority and dates only when the user gives them.
- **Reminder**: `-Section Reminders -Title "<text>"` writes a plain bullet. Put any `@time` inside the title (`-Title "Project meeting @10am"`); no other parameters apply. Remove a reminder that is done by deleting its line.

### Update

```
-Action update -Id <n> [-Title] [-Text] [-AddTag] [-RemoveTag] [-Priority] [-Start|-Scheduled|-Due] [-Status todo|in-progress] [-Section <name>] [-AddChild ...]
```

- **Start**: `-Status in-progress`, plus `-Section Sprint` if it is not already there.
- **Block**: `-Section Blocked -Text "<what it waits on>"`. `-Text` replaces the whole text, so carry over any context worth keeping.
- **Move**: `-Section Sprint|Backlog|SideQuests|Blocked` moves the line and its sub-bullets to the top of that section in the same file; status is unchanged.
- **Move to another file**: no verb does this. Say so and ask before doing anything.

### Done and Cancel

```
-Action done -Id <n>
-Action cancel -Id <n>
```

Use `cancel` for work deliberately abandoned, not deferred. When the output's `LinkedDoc` is non-null, hand that path to `vault-doc-archive` at its programmatic entry point with type `Task` and today's date. A null `LinkedDoc` (including a line that links a `Plan-` doc) means nothing to archive.

### Promote

When a task needs more than sub-bullets (findings, links, criteria), or the user asks for a task doc:

```
-Action promote -Id <n> [-Title "<doc title>"] [-Intro "<intro paragraph>"]
```

The output's `DocPath` is the new `Task-N-` doc; the line's title becomes its link. Then offer to add `## Acceptance Criteria`; if the user states criteria, add the section to the doc by hand, one `- [ ]` per criterion, above `## Notes` if present.

### Tags and Views

- **Ad hoc list**: tag each line `#list/<name>`, dated when time-boxed (`list/weekend-2026-10-17`), via `-Tags` on `add` or `-AddTag` on `update`.
- **View**: create `Inbox/View-<Name>.md` at the vault root from `templates/View-Template.md`, filling `{{Date}}` (today), `{{Title}}`, `{{Description}}` (one sentence on what it gathers), and `{{Filter}}`: `tags include #list/<name>` for a tag view, `path includes <folder>` for a single context. Write the file directly; a View note carries no directive.

### Prune

```
-Action prune [-Path <file|folder>] [-Days <n>]
```

Scope to the file in context, or the repo if the user asks for all; ask if neither is clear. This previews. List the selected items, confirm with the user, then re-run the same call with `-Apply` and report what was removed from which files.

### Check

```
-Action check [-Path <file|folder>]
```

Report problems grouped by code. Fixes: `LegacyHeading` - rename the `Active` heading to `Sprint` (keep its emoji prefix); `MissingId` or `MissingCreated` - run backfill. For the rest (`UnknownSection`, `EmptyTitle`, `CheckboxInReminders`, `DuplicateId`, `MissingDoc`, `OrphanDoc`, `DoneOutsideDone`), report and ask how to resolve.

### Backfill

```
-Action backfill [-Path <file|folder>]
```

Stamps missing IDs and created dates. Safe to re-run.

## Spin-Out to a Planning Doc

When the user asks to plan a task out, hand off to `vault-docs` (plan flow); an exploration or research task ("explore", "brainstorm", "think about") goes to its idea flow instead. When the doc exists, collapse the line with `-Action update -Id <n> -Status in-progress -Text "See [[Plan-X]]"`, keeping the title. Prefix a brief context phrase (`-Text "<context> - See [[Plan-X]]"`) when the title alone does not say what the task is about. Planned tasks link the plan directly and are never promoted to a `Task-` doc.

## Manual Edits

The user edits `Tasks.md` by hand in Obsidian. Lines without an ID are normal and get one on the next verb that touches them, a `backfill`, or a commit. Never regenerate a file, and never edit a task line by hand when a verb exists; if no verb can express the change, say so and ask.

## Init

Creates a missing `Tasks.md` for one project or area. Load `init.md` (same skill directory) for the steps.

## Portability

The script assumes only `Tasks.md` files with the canonical section headings and an optional `Inbox/` sibling for task docs. The routing index and the archive handoff after `done` are this vault's conventions and live here, not in the script.
