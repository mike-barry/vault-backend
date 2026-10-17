---
name: vault-tasks
description: Manage tasks in the vault's per-context Tasks.md files and the task views and sprints built over them. Use when the user wants to add, start, finish, cancel, block, move, or tag a task; promote a task to its own doc; ask what they are working on or what is in a sprint, group, or task view; create a task view; add a reminder; prune done tasks; check or backfill task files; or init a Tasks.md. Trigger phrases include "add a task", "mark X done", "X is blocked", "move X to current", "what am I working on", "my weekend sprint", "what's in the sprint", "show the task view", "create a task view", "add this to the sprint", "tag this for X", "promote this task", "remind me", "prune done tasks", "check task files", "init task files".
---

# Vault Tasks

A task is one checkbox line in the `Tasks.md` of the project or area it belongs to, carrying a numeric ID. Its section heading is its queue and its checkbox symbol is its status. A task that outgrows its line gets an optional `Task-N` doc. A cross-context set, such as a sprint, is a `#group/<name>` tag on its lines plus a task view, a `View-` note whose query gathers them; a view is never a copy of the lines. The full description, including line grammar and the task object fields, is [[Task-System]].

## Sections

| Section | Queue |
|---------|-------|
| `Reminders` | Plain bullets, no checkbox or lifecycle; `@time` anchors a time-sensitive one. |
| `Current` | Pulled from the backlog and committed, started or not. |
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

- **Arrays** are passed as one delimited string: `-Tags`, `-Tag`, `-AddTag`, `-RemoveTag`, `-Section`, `-Status`, `-Id` are comma-separated (`-Tags "group/weekend-2026-10-17,errand"`); `-Children` and `-AddChild` are newline-separated (in Bash, `-Children $'First\nSecond'`). Tags may be given with or without `#`.
- **Values** are case-insensitive. Sections: `Current`, `Blocked`, `Backlog`, `SideQuests`, `Done`, `Reminders`. Statuses: `todo`, `in-progress` (`list` also takes `done`, `cancelled`). Priorities: `highest`, `high`, `medium`, `low`, `lowest`, `none`. Dates are `yyyy-MM-dd`, or `none` to clear.
- **Output** is one JSON document on stdout. Summarize it for the user; never paste raw JSON.
- **Errors** exit 1 with the explanation on stderr. Relay it verbatim and stop; never fall back to editing the file by hand.
- **Address tasks by ID**, found with `list` when the user names a task by its words.

## Routing a New Task

In this vault, load `Projects/Projects.md` and route to the `Tasks.md` of the active project the task clearly belongs to; otherwise load `Areas/Areas.md` and route to the matching area. Ask when ambiguous. If the target `Tasks.md` is missing, run [[#Init]].

## Verbs

### List

"What am I working on", "show tasks for X":

```
-Action list [-Path <file|folder>] [-Section Current,Blocked] [-Status todo,in-progress] [-Tag group/<name>] [-Id 17,18]
```

Default scope is the whole repo. Lines with a null `Id` are hand-written and not yet stamped; they are still real tasks.

### Add

```
-Action add -Path <Tasks.md|folder> -Title "<title>" [-Text "<context>"] [-Section <name>] [-Status in-progress] [-Tags ...] [-Priority ...] [-Start|-Scheduled|-Due <date>] [-Children ...]
```

- Section defaults to `Backlog`; use `Current` when the user says now or next, `Blocked` or `SideQuests` when that fits.
- Pass priority and dates only when the user gives them.
- **Reminder**: `-Section Reminders -Title "<text>"` writes a plain bullet. Put any `@time` inside the title (`-Title "Project meeting @10am"`); no other parameters apply. Remove a reminder that is done by deleting its line.

### Update

```
-Action update -Id <n> [-Title] [-Text] [-AddTag] [-RemoveTag] [-Priority] [-Start|-Scheduled|-Due] [-Status todo|in-progress] [-Section <name>] [-AddChild ...]
```

- **Start**: `-Status in-progress`, plus `-Section Current` if it is not already there.
- **Block**: `-Section Blocked -Text "<what it waits on>"`. `-Text` replaces the whole text, so carry over any context worth keeping.
- **Move**: `-Section Current|Backlog|SideQuests|Blocked` moves the line and its sub-bullets to the top of that section in the same file; status is unchanged.
- **Move to another file**: no verb does this; see [[#Manual Edits]].

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

### Groups, Sprints, and Task Views

A group is a `#group/<name>` tag on each member line, dated when time-boxed (`group/weekend-2026-10-17`). A task view is a `View-<Name>.md` note holding a Tasks plugin query; whether it is a sprint, a weekend, or every open task is the view's own title and description, not the tag's.

```
-Action groups [-Path <file|folder>]
```

- **Find a sprint or task view** ("what's in my weekend sprint", "show the task view"): run `groups` to see every group with its open and closed counts and the view notes that reference it, then `-Action list -Tag group/<name>` for the lines. Views live in the root `Inbox/` while new and in a root `Tasks/` folder once durable; `groups` reports their paths, so no globbing is needed.
- **Add to a group** ("add this to the sprint"): `-Tags` on `add` or `-AddTag` on `update`.
- **Create a task view**: copy `templates/View-Template.md` to `Inbox/View-<Name>.md` at the vault root, filling `{{Date}}` (today), `{{Title}}` (say what it is, e.g. `Sprint Weekend 2026-10-17`), `{{Description}}` (one sentence on what it gathers), and `{{Filter}}`: `tags include #group/<name>` for a group, `path includes <folder>` for one context. Write the file directly; a View note carries no directive.

### Prune

```
-Action prune [-Path <file|folder>] [-Days <n>]
```

Scope to the file in context, or the repo if the user asks for all; ask if neither is clear. This previews. List the selected items, confirm with the user, then re-run the same call with `-Apply` and report what was removed from which files.

### Check

```
-Action check [-Path <file|folder>]
```

Report problems grouped by code. Fixes: `LegacyHeading` - rename the `Active` or `Sprint` heading to `Current` by hand, keeping its emoji prefix; `MissingId` or `MissingCreated` - run backfill. Any other code: report it and ask.

### Backfill

```
-Action backfill [-Path <file|folder>]
```

Stamps missing IDs and created dates. Safe to re-run.

## Spin-Out to a Planning Doc

When the user asks to plan a task out, hand off to `vault-docs` (plan flow); an exploration or research task ("explore", "brainstorm", "think about") goes to its idea flow instead. When the doc exists, collapse the line with `-Action update -Id <n> -Status in-progress -Text "See [[Plan-X]]"`, keeping the title. Prefix a brief context phrase (`-Text "<context> - See [[Plan-X]]"`) when the title alone does not say what the task is about. Planned tasks link the plan directly and are never promoted to a `Task-` doc.

## Manual Edits

The user edits `Tasks.md` by hand in Obsidian; lines without an ID are normal. The agent never regenerates a file and never edits a task line directly when a verb exists. The one sanctioned direct edit is renaming a legacy section heading. For anything else no verb can express, such as moving a task to another file, say so and ask.

## Init

Creates a missing `Tasks.md` for one project or area folder. Errors if the file already exists; output is plain text, not JSON.

```
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-tasks/scripts/init-tasks.ps1 -Path "<folder>"
```
