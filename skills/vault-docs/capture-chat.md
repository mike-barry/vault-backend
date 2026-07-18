# Chat Capture Flow

Save the current conversation as a structured markdown note in the vault. Triggered when the user explicitly asks to preserve the conversation — "save this chat", "save this conversation", "save this as a note", "capture this conversation", "create a note from this". Do not invoke proactively.

## Steps

### 1. Analyze the Conversation

Read the full conversation context and draft the following:

- **Title**: A concise, descriptive display title (e.g. "Vault Save Chat Skill Design")
- **Filename**: `Chat-Title.md` — the `Chat` type prefix, then a short title in `Title-Case-With-Hyphens` (e.g. `Chat-Vault-Save-Chat-Skill-Design.md`). Append a trailing date (`Chat-Title-YYYY-MM-DD.md`) only when the date is meaningful to identify the note.
- **Date**: Today's date in YYYY-MM-DD format (written to `doc.created` frontmatter, alongside `doc.type: Chat` — schema per [[Document-Conventions]])
- **Summary**: Key points covered — what was discussed, learned, or explored
- **Decisions**: Any concrete decisions made (omit section if none)
- **Action Items**: Any next steps or todos identified (omit section if none)

### 2. Resolve the Destination

Decide where the note should live. A captured chat is an **active artifact** that lives in `Inbox/` and is archived manually when no longer needed.

- **Does the conversation clearly relate to a project or area?** Judge from what was discussed and the files or notes touched. Load `Projects/Projects.md` to check active projects first; then load `Areas/Areas.md` to identify areas (`Personal`, `Hobbies`, `Homelab`, `Research`, `Vault`, `Work`).
- **Clear project or area** → default to that folder's `Inbox/` subfolder (e.g. `Areas/Homelab/Inbox/`, `Projects/<Project>/Inbox/`).
- **No clear home** → default to `Areas/Research/Inbox/`.

This is only the *default*; the user confirms it in the next step.

### 3. Confirm with the User

Present the draft before writing anything, showing the resolved destination:

```
Here's what I'll save:

**File:** Areas/Homelab/Inbox/Chat-Pi-Hole-Local-DNS-Setup.md
**Title:** Pi-Hole Local DNS Setup

**Summary:**
- ...

**Decisions:**
- ...

**Action Items:**
- ...

Does this look right? Any changes to the title or content?
Also — do you want a full transcript appended at the bottom?
Destination: Areas/Homelab/Inbox/ — confirm or pick another location.
```

Always prompt to confirm the destination, whether it resolved to a project or area's `Inbox/` or fell back to `Areas/Research/Inbox/`. Wait for the user to confirm or redirect before proceeding.

**If the conversation is substantive enough that a structured doc might serve better than a chat capture**, offer an upgrade before saving. Use the signal strength of the conversation to decide which offer to make:

- **Clearly a planning session** — decisions locked, open implementation work ahead, a defined finish line in view: offer the planning flow only.
  > This looks like a planning session. Want me to spin it into a planning doc instead of capturing it as a chat record?

- **Clearly exploratory** — thinking out loud, pre-commitment, no firm decisions, brainstorming or surveying options: offer the idea flow only.
  > This reads more like exploratory thinking than a committed plan. Want me to capture it as an idea doc instead?

- **Ambiguous but elevated** — substantive enough that either a plan or an idea doc would serve better than a flat chat capture, but the conversation doesn't clearly commit to a course of action: offer both and let the user choose.
  > This is substantive enough that a structured doc might serve you better than a chat capture. Want to promote it to a **planning doc** or an **idea doc** instead? Or keep it as a chat capture?

The distinction to apply: a **plan** is a frozen decision record with implementation work ahead; an **idea** is an obligation-free space for pre-commitment thinking. If the conversation landed on specific decisions and next steps, it's a plan. If it was exploration without commitment, it's an idea. Default to capturing the chat if the signal is weak or the user declines the offer. If the user accepts, continue within this skill using the matching flow (plan or idea) and stop the chat-capture flow.

### 4. Write the Note

Use the confirmed content to write the file at the destination resolved in Step 2. An explicit user-specified folder always overrides the resolved default.

**Template:**

```markdown
---
doc.created: YYYY-MM-DD
doc.type: Chat
---

# [Title]

**Source:** Chat transcript - YYYY-MM-DD

## Summary

[Key points as bullets or a short paragraph]

## Decisions

- [Decision 1]
- [Decision 2]

## Action Items

- [x] [Action item already completed during the chat]
- [ ] [Action item still open]

## Transcript

[Only include if the user requested it — see transcript rules below]
```

Omit **Decisions** and **Action Items** sections entirely if there's nothing to put in them. Check (`- [x]`) any action item that was already completed during the chat; leave open items unchecked (`- [ ]`).

After writing the file, inject the skill-owned-file directive by running `scripts/add-skill-directive.ps1 -DocPath <path> -When 'editing this file'`.

### 5. Surface Open Action Items as a Task

Open action items shouldn't be buried in a frozen archived note, so they become a live task:

- **Only if one or more action items remain unchecked**, hand off to the `vault-tasks` skill to add a task that links back to this note via `[[NoteName]]`. If every action item was completed in-chat (all checked), or there are none, skip this step — there's nothing live to track.
- `vault-tasks` routes the task with its normal routing tree — usually the same project or area this note was filed under; for a homeless chat it routes or asks as usual.
- Leave the full Action Items list in the note as the frozen record (checked and unchecked); the spawned task is the live pointer for the open items.

### 6. Transcript Rules (if Requested)

If the user wants the full transcript included, append it as a `## Transcript` section at the bottom. Follow these rules:

- Include verbatim user and assistant turns with speaker labels (`**User:**`, `**Assistant:**`)
- Omit or collapse tool call output — replace with a one-line note like `_[read 3 files]_` or `_[ran git pull]_`
- Strip system reminders and harness metadata entirely
- If early conversation was compressed, insert `_[Earlier context summarized]_` at that point
- Do not editorialize — transcript content should be faithful to what was said
