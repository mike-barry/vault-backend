# Load Flow — Fallback

Reached only when SKILL.md's fast path didn't find exactly one direct wildcard match (no match, or multiple candidates).

1. Read `Resources/Vault/Modes/Modes.md` to get the full inventory.
2. Match the requested name against available modes — exact first, then fuzzy/substring.
3. If multiple candidates match: use `AskUserQuestion` with the matching mode names as options.
4. If no match: use `AskUserQuestion` to offer either creating a new mode (→ [create.md](create.md)) or naming a different one from the inventory shown.
5. Once resolved to one mode file, load it the same way the fast path does:
   - **New session branch** — if the user asked to open a new session with this mode (e.g. "load X mode in a new session", "spawn a session in X mode"): resolve the mode file's absolute path and delegate to `spawn-session` with `--append-system-prompt-file <abs-path>`. Multiple modes: one flag per mode, personality modes before context modes.
   - **In-session branch** (default) — read the mode file and inject its full contents into the current session as a user message.
