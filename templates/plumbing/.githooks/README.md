# README.md - Line-Ending Normalization Hook

A `pre-commit` hook that makes files agree with the line endings their repository declares. One self-contained script, written to be copied between repos unchanged.

## Why It Exists

`.gitattributes` normalizes line endings **in the index**, so commits are always correct. It does not touch the working tree, which keeps whatever the writing tool produced. On Windows that means `Set-Content`, shell redirection, and most native editors leave CRLF on disk indefinitely, since git only rewrites a working-tree file on checkout.

That on-disk drift is invisible to git and harmless to a commit, but it reaches anything reading the file outside git, including a script copied to a Linux host.

## How It Decides

The target comes from `git check-attr text eol binary`, so the script carries no configuration and needs no edits when moved to another repo. A repo enforcing CRLF gets CRLF from the same script that gives this one LF.

A file is converted only when the repo declares an `eol` attribute for it, **and** git itself would convert it. Left alone:

- Files marked `binary`, or with `text` explicitly `unset`
- Files with no declared `eol`, where the working-tree ending is deliberately platform-dependent
- Symlinks, which would otherwise be written through to their target
- Under `text=auto`, files git would class as binary: a NUL byte anywhere, a CR that is not part of a CRLF, or too high a proportion of non-printable bytes
- Files that cannot be read or written
- The hook's own file, for the reason under Known Limitations

Under `text=auto` git also calls a file binary when non-printable bytes outweigh printable ones by more than 1:128, and the hook applies that test too. All three are git's own conditions for refusing eol conversion, and they apply only under `text=auto`. Matching them is what stops the hook mangling a binary type that is missing from `.gitattributes`, and what stops it eating a byte from a file with mixed line endings. `git check-attr` reports the declared attribute and never runs that detection itself, so the checks have to be made here.

Under an **explicit** `text` attribute git converts regardless of content, so the hook does too. Declaring `*.md text eol=lf` is a statement that those files are text, and git takes it at its word. Applying the `auto` rules there would leave the working tree permanently disagreeing with the index.

Setting `eol` implies `text`, so a rule of `*.md eol=lf` alone is honored even though `check-attr` reports `text: unspecified` for it.

A file is rewritten only when its bytes actually change, which keeps mtime stable and avoids waking editors and file watchers. A staged file that also has unstaged changes is skipped rather than converted, so the hook cannot stage work that was deliberately held back.

The hook never blocks a commit. Anything it cannot do is reported on stderr rather than passing silently.

## Manual Use

Git invokes the script with no arguments, which handles everything staged. Passing paths fixes those files instead, which is the escape hatch for a file written by a shell command between commits:

```
.githooks/pre-commit path/to/file
```

Relative paths resolve against the current directory, so this works from anywhere in the tree. Paths git cannot resolve, including absolute MSYS-style paths and anything outside the repository, are reported rather than skipped in silence.

## Setting It Up In Another Repo

1. Copy the `pre-commit` script into a `.githooks/` directory at the repo root, and commit it.
2. Confirm the repo's `.gitattributes` declares an `eol` attribute, since the hook does nothing without one:

   ```
   * text=auto eol=lf
   ```

   Substitute `eol=crlf` for a repo that enforces CRLF. The hook follows whichever is declared.
3. Mark it executable in the index, so it also runs on Linux:

   ```
   git update-index --chmod=+x .githooks/pre-commit
   ```
4. Point git at the folder. **This is local config and is not committed, so it has to be run once per clone:**

   ```
   git config core.hooksPath .githooks
   ```

Step 4 is the one that gets missed. A fresh clone on another machine runs with no hooks and gives no indication of it, so it is worth naming in the repo's own README.

## Requirements

`sh`, `awk`, `perl`, and git 2.25 or later for `git add --pathspec-from-file`. Git for Windows supplies all of them, as does any mainstream Linux distribution.

The file work is done in Perl rather than `sed` because MSYS `sed` translates line endings when it reads, so under Git for Windows it cannot see a file's real bytes and silently drops a CR from a file with mixed endings. Perl in binmode reads what is actually there.

Process startup dominates the runtime on Windows, so the hook spawns a fixed number of processes rather than a few per file. A 400-file commit takes well under a second, and an unrelated dirty file in the tree no longer costs anything.

macOS is untested. The BSD-versus-GNU `sed` incompatibility that would have broken it no longer applies, since `sed` is no longer used, but nothing here has been run on a Mac.

## Known Limitations

Deliberately not handled, because the fix would cost more complexity than the case is worth.

- **The hook does not normalize itself.** `sh` reads a script incrementally by byte offset, so rewriting the file mid-run makes the shell resume at the wrong place and fail the commit. The file is skipped with a message on stderr. Fix it by hand, or let a checkout do it.
- **A `text` attribute with no `eol` is left alone.** Git still has a target in that case, from `core.eol` or the platform default, so the working tree can differ from a fresh checkout. The hook acts only on a declared `eol`, because absent one the repository has not stated a working-tree preference and guessing could mass-convert a repo that never asked. `eol=native` *is* honored, resolved the same way git resolves it.
- **Rebase, cherry-pick, and revert bypass the hook.** Git does not run `pre-commit` for sequencer-driven commits. Conflict resolution is a common source of drift on Windows, so this is a real gap, not a theoretical one. Run the hook by hand afterward if it matters.
- **`.gitattributes` is read from the working tree, not the index.** Staging a change to `.gitattributes` and relying on it in the same commit gives the old rules for that commit.
- **Hardlinks are broken, not followed.** A converted file is replaced by a rename, so a hardlinked twin keeps the old content rather than changing with it. File mode is carried across; the inode is not.
- **Filenames git has to quote are skipped**, with a message. That means names containing a tab, a newline, or a double quote. Unquoting them here would risk naming a different file, so the hook refuses rather than guesses.
- **Files declaring `working-tree-encoding` are skipped**, with a message. Git converts line endings on the decoded text while the hook sees raw bytes, so rewriting them would inject CR bytes into the middle of a character stream.
- **A file whose committed blob already contains CRLF gets renormalized.** Git's own `git add` deliberately leaves those alone; the hook converts them the first time it touches them. That is what the hook is for, but it is a case where it does more than git would.
- **A hard kill can leave a `.eol-tmp-<pid>` file** beside the one being converted. Interrupts are trapped, but `SIGKILL` cannot be. A later `git add -A` would pick it up, so delete it if you see one.
- **Running with explicit paths does not refresh git's status.** A file converted that way can show as modified until you `git add` it again, for the same stat-cache reason as the entry below. Its content is correct.
- **A pathspec-limited commit** (`git commit -- some/path`) leaves the file showing as modified until you `git add` it again. Git gives the hook a temporary index in that mode, so the refreshed stat data never reaches the real one, and it does not clear on its own. The committed content is correct; only the status display is wrong.

## What It Does Not Do

It does not suppress the staging warning:

```
warning: in the working copy of '<file>', CRLF will be replaced by LF the next time Git touches it
```

That is emitted by `git add`, and no git hook runs earlier than `pre-commit`. The warning is correct and needs no action, but agents and people both tend to read it as a defect and go looking for something to fix. Say so directly in whatever guidance the repo gives its agents.
