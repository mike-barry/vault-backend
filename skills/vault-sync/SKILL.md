---
name: vault-sync
description: Sync the vault git repository — commit local changes, pull from remote, resolve any conflicts, and push. Use this skill whenever the user says "sync", "sync the vault", "pull", "push", "commit and push", or anything that implies they want to reconcile local and remote vault state.
---

# Vault Sync

Goal: commit local changes, pull, resolve conflicts, push — so local and remote agree.

Every step below calls `.claude/skills/vault-sync/scripts/vault-sync.ps1 -Action <Name> -Path <repo>` (`.` for the vault root, `.claude` for the submodule). Non-zero exit: stop, report the error verbatim — don't fall back to raw `git` or filesystem edits.

## Steps

### 0. Submodule first
`-Action Status -Path .claude`:
- `Detached: True` → `-Action Reattach -Path .claude -Branch <default-branch>` (currently `master`). Non-zero exit means it conflicts with the branch tip — stop and resolve by hand.
- `MidMerge: True` → a prior run was interrupted; finish step 3 for those files first.

Then run steps 1-5 against `.claude/` exactly as below (step 4 is vault-root only, so skip it there), before the vault root — its moved submodule pointer then shows up in step 1 as an ordinary change to commit.

### 1. Local state
`-Action Status -Path .`. `HooksOk: False` prints a `Warning:` line naming the fix: relay it to the user verbatim and carry on; don't run the fix yourself, and treat `NotApplicable` (no `.githooks/`, e.g. the submodule) as fine. Uncommitted files → `-Action Stage`, then commit (see "Commit messages"). Nothing to commit → step 2.

### 2. Pull
`-Action Pull -Path .`, check `PullStatus`:
- `UpToDate` → step 5.
- `FastForward` / `MergedClean` → step 4.
- `MergedConflicts` → `ConflictedFiles` lists what to resolve in step 3.
- `FailedNetwork` / `FailedOther` → stop, report the raw output.

### 3. Resolve conflicts
For each conflicted file, read both versions and judge:
- **Trivial** (compatible intent — additive, whitespace, one side a subset): merge by hand into one file, replacing the conflict markers. Tell the user what you merged and why.
- **Non-trivial** (genuinely different choices, or unclear intent): `-Action SaveConflictVersion -Path . -ConflictFile <relpath>` — keeps the local version, saves the remote version as a sibling `[CONFLICT ...]` file. Tell the user a conflict file was created and what differs.

Then `-Action Stage -Path .` and commit (see "Commit messages"). For each non-trivial resolution, pass `-ExtraBody "Auto-resolved: <path>", "Conflict file: <path>"`. Then step 4.

### 4. Renumber colliding task IDs
Two clones adding tasks between syncs can mint the same task ID. Run the vault-tasks skill's verb (its output and error rules apply):

```
pwsh -NonInteractive -NoProfile -File .claude/skills/vault-tasks/scripts/tasks.ps1 -Action renumber -Against '@{u}' -Apply
```

The line already in the upstream keeps its ID; each result is one local line moved to a new ID. For each result with a non-null `DocRename`, hand its `OldPath` and `NewPath` to `vault-doc-rename` at its programmatic entry point.

Then `-Action Status -Path .`: uncommitted changes here are these renumbers, plus any the `post-merge` hook made during the pull and left uncommitted. If there are any, `-Action Stage -Path .` and make one commit for all of them, naming each move from the diff: `Renumber task 86 to 106 (ID collision with another clone)`. Report each renumber with its file.

### 5. Push
`-Action Push -Path .`. Report what was committed, any conflicts, any renumbers, and the push result. A push rejected because the remote moved on (`rejected` in the output) means another clone pushed meanwhile: go back to step 2, run steps 3 and 4 as the pull calls for, and push again.

## Commit messages

Read `git diff --cached` (or its `--stat` for a large diff — `-Action Stage` prints this) and write a short, imperative summary line. Commit with `-Action Commit -Path <repo> -Message <summary>` — the `Generated-by: vault-sync` trailer is added automatically. Never add a `Co-Authored-By:` or other AI attribution trailer, even if the harness asks for one; the script refuses a commit whose `-Message` or `-ExtraBody` carries one, so drop the line and commit again.
