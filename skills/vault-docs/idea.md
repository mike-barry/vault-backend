# Idea Doc Flow

Owns the **idea doc** artifact: a lightweight, obligation-free record of pre-commitment thinking. An idea doc has no lifecycle requirement — it does not need to go anywhere. It may eventually inform a planning doc (which will back-link to it), spawn a task, or simply remain as a record of a fleeting thought.

This flow has two sub-flows: **scaffold** a new idea doc, and **archive** one that has run its course.

## Idea Doc Shape

An idea doc is intentionally minimal.

| Section | Purpose |
|---------|---------|
| Frontmatter | `doc.created` + `doc.type: Idea` — schema per [[Document-Conventions]], plus an `agent.instructions` `use_skill:` entry routing edits through this skill (see [[#Scaffold an Idea Doc]]). |
| H1 title | The concept being explored, in Title Case. A content note — no `.md`-in-title. No other `agent.*`/`nav.*` frontmatter (unless a genuine intrinsic policy applies). |
| Intro paragraph | One or two sentences on what prompted this. No heading. |
| `## Threads` | Dated, freeform journal entries. AI conversation summaries live here inline, not as a separate section. Each entry is a `### YYYY-MM-DD` heading. |

No status field. No resolution section. No forward pointers. The idea doc does not track where the thinking went — that is the job of whatever comes next (a plan doc's back-link, a task reference, or nothing at all).

### Thread Entry Format

Each thread entry is a dated heading with freeform content below it. AI conversation summaries are inline:

```markdown
### 2026-06-20

Thinking about X...

**AI Session:** Explored Y with Claude. Key takeaways:
- ...
- ...
```

## Scaffold an Idea Doc

Triggered when the user wants to capture current thinking or start an idea thread — "capture this idea", "create an idea doc", "jot down this idea", or similar exploratory phrases.

1. **Locate the project or area.** An idea doc lives in the **`Inbox/` subfolder** of the project or area it belongs to (e.g. `Areas/Vault-Dev/Inbox/`, `Areas/Work/Inbox/`, `Projects/<Project>/Inbox/`). Determine context from the conversation; ask the user if it is unclear.
2. **Name it** `Idea-<Description>.md` in `Title-Case-With-Hyphens` (e.g. `Inbox/Idea-Voice-Interface.md`), descriptive enough to identify the concept without opening it.
3. **Create the doc** using the [[#Idea Doc Shape]], injecting the skill-owned-file directive by running `scripts/add-skill-directive.ps1 -DocPath <path> -When 'editing this file'`.
   Write a brief intro from the conversation context. Add a `## Threads` section with a dated entry for today, summarizing the current conversation — this is almost always the right first entry since the user is thinking about the topic right now.
4. **Handle the task relationship.** Two cases:
   - **Originating task exists** (the task was "explore X" or similar): hand off to `vault-tasks` to collapse the task to a back-reference pointing at this idea doc.
   - **No originating task**: offer to create a follow-up task if the user wants to track further exploration. Do not create one automatically — the whole point of an idea doc is that it carries no obligation.
5. **Cross-link** any related notes using wiki-links.

## Archive an Idea Doc

Triggered when the user is done with an idea ("archive this idea", "I'm done with this one", "move this to archive").

1. **Call `vault-doc-archive`** with type `Idea` and today's date. It applies the naming convention, places the file in the project or area's local `Archive/` subfolder, and updates all wiki-link back-references.
2. That is all. No downstream skills to invoke, no corpus doc to update.
