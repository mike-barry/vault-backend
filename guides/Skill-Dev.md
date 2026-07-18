---
doc.created: 2026-06-28
---
# Skill-Dev.md - Managing Vault Skills

Claude Code skills live in `.claude/skills/` inside the vault repo - not in `~/.claude/` or other user-level directories. Each skill is a subfolder containing a `SKILL.md` file. The harness auto-discovers skills from this location and makes them available to Claude via the `Skill` tool.

Never hard-wrap prose lines in SKILL.md files - see [[Document-Conventions]].

## Structure

```
.claude/skills/
  <skill-name>/
    SKILL.md          - required; frontmatter (name, description) and skill steps
    scripts/          - optional; supporting scripts for this skill
    templates/        - optional; template files used by this skill
  _shared/            - topic-scoped vault-xxx.ps1 helper scripts used across multiple skills
    tests/            - direct unit tests for _shared scripts, one file per vault-xxx.ps1
```

### Frontmatter Fields

`name` and `description` are required on every `SKILL.md`. Two optional fields control visibility, checked by `vault-skill-audit`:

- **`disable-model-invocation: true`** - the model can never auto-fire this skill; it only runs via explicit invocation (a slash command, or a direct "run X"). Reserve for skills meant to be triggered *only* that way, regardless of risk - not a stand-in for "this is risky." A high-risk but request-triggerable skill (e.g. `vault-sync` firing on "sync the vault") should stay model-invocable and instead confirm with the user before its irreversible step, same as the harness's own explicit-permission rules. Also keeps the skill out of the always-loaded skill listing in every conversation's context, since the model no longer needs to see it to decide whether to invoke it.
- **`user-invocable: false`** - hides the skill from `/menu`. Use for skills that are pure background knowledge or programmatic-only building blocks a user would never `/run` directly (e.g. logic another skill hands off to).

## Naming Convention

All vault skill names must start with `vault-`. Examples: `vault-sync`, `vault-project-archive`.

## Shared Scripts

`.claude/skills/_shared/` is a family of topic-scoped `vault-xxx.ps1` files, not one growing `vault-common.ps1`. As shared logic accumulates, group it by what it operates on and give each domain its own file (e.g. `vault-frontmatter.ps1` for functions that read or write frontmatter content).

### Where a Function Belongs

Ask whether the function reads or writes file *content* in a specific domain:

- **Yes** - it belongs in that domain's `vault-xxx.ps1` file. Example: parsing a frontmatter
    fence, reading or writing a frontmatter field, and a date-recovery chain whose first step checks an existing frontmatter value all belong in `vault-frontmatter.ps1`.
- **No** - it is generic filesystem, path, or string logic with no dependency on a
    content domain, even if its only caller today happens to be a domain-scoped helper. It belongs in `vault-common.ps1`. Example: extracting a date from a filename, normalizing a path for comparison, and testing whether a file is a folder note by its position on disk are all content-independent and belong in `vault-common.ps1`, not the domain file that calls them.

Git-plumbing logic (pull/push/commit orchestration, merge-conflict handling, branch state) is not pre-classified into `vault-common.ps1` by default - it's substantial enough to warrant its own topic-scoped `vault-git.ps1` once a second skill actually needs it, per "Extract, Do Not Duplicate" below. Until then it stays local to the one skill using it (e.g. `vault-sync`'s scripts), since promoting it speculatively for a single consumer is the premature abstraction this section is trying to avoid elsewhere.

### Extract, Do Not Duplicate

Before adding a new shared function, check whether an existing skill script already has a private or ad hoc version of the same logic (a regex-based date extractor, a hand-rolled frontmatter read, etc.). Extract that logic into the shared file and refactor the original script to call it, rather than writing a second copy alongside it. Rerun the original script's unit tests afterward to confirm the extraction is behavior-preserving.

`vault-skill-audit` automates this check for a given skill - flagging both duplication of existing `_shared` logic and functions that are promotion candidates - and, when a promotion is applied, sweeping other skills' scripts for logic the newly-shared helper could also replace.

### Testing Shared Scripts

Every `vault-xxx.ps1` file in `_shared/` gets its own direct unit test file in `_shared/tests/`, run independently of any consuming skill. Relying only on a consuming skill's `unit-tests.ps1` to exercise shared logic is not sufficient - coverage then only extends to whatever that one consumer happens to call, edge cases no current consumer triggers go untested, and a break in the shared file surfaces as a confusing failure in an unrelated skill's suite rather than pointing at the actual broken function. Name the test file after the topic it covers (e.g. `vault-credentials.unit-tests.ps1` for `_shared/vault-credentials.ps1`), and use the same `Run-Test`/`Assert-That` conventions as skill-level tests (see `vault-test-common.ps1`) - falling back to a local minimal runner when a shared script's state isn't file-based and doesn't fit the worktree-isolation helpers (`Initialize-TestWorktree`, `Reset-TestFolder`), as with Windows Credential Manager state in `vault-credentials.ps1`'s tests. Skills that depend on a shared function should still keep it exercised in their own tests too - that verifies integration, not the shared function's correctness in isolation, which is what the direct test in `_shared/tests/` is for.

## Migrating a Skill to Wrap an MCP Tool

When an MCP server exposes an operation a skill previously implemented via script, hollow the skill out: delete the script and its tests, and rewrite `SKILL.md` to call the tool directly, keeping only judgment, trigger phrasing, and confirmation logic in the skill body. Do this as a single clean swap, not a dual-path fallback to the old script - once the tool has its own dispatch-test coverage, a "try MCP, fall back to script" branch just adds two logic paths that can drift and a cleanup TODO likely to be forgotten; a plain skill-file edit is trivially `git revert`-able if something regresses post-cutover. `vault-doc-rename` -> `mcp__vault-mcp-server__rename_note` is the precedent.

## Editing a Skill

`SKILL.md` and any co-located reference doc describe the skill's **current** behavior only. When behavior changes, rewrite the affected wording to describe the new behavior directly - trim toward that target state rather than leaving a "used to work like X, now works like Y" narrative in the reference text, and don't keep superseded examples or field names around as historical context. Git history and the driving planning doc's Locked Decisions are where that story belongs.

## Adding a Skill

1. Create a subfolder under `.claude/skills/` using the `vault-*` naming convention.
2. Add a `SKILL.md` file with frontmatter (`name`, `description`) and the skill steps.
3. If the skill needs scripts, add a `scripts/` subfolder and write scripts in PowerShell (`.ps1`). Scripts should have accompanying unit tests.
4. If the script logic is reusable across skills, place it in the appropriately-scoped `vault-xxx.ps1` file under `.claude/skills/_shared/` (see Shared Scripts above) rather than defaulting to `vault-common.ps1`.
5. If the skill uses template files, place them in a `templates/` subfolder.
6. Run `/vault-skill-audit <skill-name>` against the new (or changed) skill to check it for visibility (should high-risk or purely-programmatic skills carry `disable-model-invocation` or `user-invocable: false`?), determinism (are any fixed transforms still agent-prose instead of scripted?), and composability (does it duplicate or belong in `_shared`?).

The harness auto-discovers skills from `.claude/skills/` - no manual registration needed.
