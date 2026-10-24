# vault-backend

The agent layer for my personal knowledge base: the Claude Code skills, guides, hooks, and scaffold templates that let an AI agent read, write, and maintain a markdown vault by its conventions.

> **Status:** This is a personal project in continuous development, not a finished product. It is built for my own vaults and my own workflow, its interfaces change as I learn what works, and parts of it are experiments. It is public so the work can be seen, not as a supported tool.

## What It Is

I keep my notes, projects, and plans in an [Obsidian](https://obsidian.md) vault: a git repo of markdown files in a [PARA](https://fortelabs.com/blog/para/) layout (Projects, Areas, Resources, Archive). Much of the day-to-day work on that vault is done by an AI agent, [Claude Code](https://www.anthropic.com/claude-code), running inside the repo.

An agent left to itself edits a vault inconsistently, so this repo holds the vault's agent-facing rules and tools. It mounts as a git submodule at `.claude/` in each vault, which is where Claude Code looks for project skills and settings, so several vaults share one backend and each pins the commit it runs on.

- **Guides** state the rules an agent follows: how to navigate by the vault manifest and note frontmatter, document conventions, where content belongs, and how to write a skill.
- **Skills** turn recurring vault operations into repeatable procedures. Each is a `SKILL.md` the agent reads, usually backed by a PowerShell script that does the deterministic part, so the model decides what to do and the script does it the same way every time.
- **Hooks and settings** run at session start to pull the latest vault and backend before the agent begins.
- **Templates** seed a new vault with its manifest, registries, guides, git plumbing, and lint state.

## Layout

```
CLAUDE.md      - bootstrap; @-includes the vault's guide and manifest
settings.json  - shared hooks and permissions
skills/        - vault-* skills, _shared PowerShell libraries, and their tests
guides/        - -Template copies of the guides a vault operates by
templates/     - seed files for standing up a new vault
```

## Skills

| Skill | Purpose |
|---|---|
| `vault-docs` | Creates and closes out the vault's document types: planning, idea, corpus, chat captures, and reading notes |
| `vault-tasks` | Manages per-project `Tasks.md` files, task IDs, and task views, compatible with the Obsidian Tasks plugin |
| `vault-lint` | Fixes typography, whitespace, and filenames; detects broken wiki-links |
| `vault-sync` | Commits, pulls, resolves conflicts, and pushes the vault and its backend submodule |
| `vault-doc-rename`, `vault-doc-archive` | Move, rename, or archive a note while keeping every `[[wiki-link]]` to it intact |
| `vault-project-new`, `vault-project-archive` | Create and retire projects and areas with their standard folders and registry entries |
| `vault-agent-frontmatter` | Maintains the YAML frontmatter agents use to route between notes |
| `vault-mode` | Loads session modes that add background and instructions to a conversation |
| `vault-bug`, `vault-skill-audit` | Capture agent misbehavior as root-caused tickets, and audit a skill's design |
| `vault-mcp`, `vault-claude-auth`, `spawn-session` | Operational support: the vault MCP server connection, login renewal, and spawning sessions |

`vault-calendar` and `vault-transcript-fetch` are proofs of concept, not working skills.

## Running the Tests

The shared libraries and most skill scripts have unit tests written as plain PowerShell 7 scripts. Each runs on its own and isolates its changes in a throwaway git worktree, so run it from inside a vault that mounts this repo at `.claude/`:

```
pwsh -NoProfile -File .claude/skills/_shared/tests/vault-tasks.unit-tests.ps1
```

## Related

- [vault-server](https://github.com/mike-barry/vault-server) - an MCP server, in C#/.NET, that exposes the vault to agents over the Model Context Protocol

## About

Built and maintained by Mike Barry as a personal project.
