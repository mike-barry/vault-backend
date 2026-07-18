---
name: vault-mode
description: >
  Load, list, create, or update session context modes. Modes inject background facts,
  behavioral instructions, and framing into the current session or a newly spawned one.

  Invoke for:
  - **Load** — "load work mode", "switch to vault-dev mode", "put me in HAL mode",
    "load work mode in a new session", "spawn a session in vault-dev mode"
  - **List** — "what modes are available", "list modes", "show me the modes"
  - **Create** — "create a new mode", "add a mode for X", "new mode called X"
  - **Update** — "add this as an instruction to X mode", "update the X mode to",
    "add X to the Y mode", "remove X from the Y mode"
---

# vault-mode

Manages session context modes stored in `Resources/Vault/Modes/`, named `Mode-<Name>.md`.

## Fast path — direct load

Try this first whenever the request names a specific mode to load (not list/create/update, and not asking "what modes are there").

1. Glob `Resources/Vault/Modes/Mode-*<name>*.md` (case-insensitive) against the requested name.
2. **If exactly one file matches**, load it directly — do not read `Modes.md` or any file under `flows/`:
   - **New session branch** — if the user asked to open a new session with this mode (e.g. "load X mode in a new session", "spawn a session in X mode"): resolve the mode file's absolute path and delegate to `spawn-session` with `--append-system-prompt-file <abs-path>`. Multiple modes: one flag per mode, personality modes before context modes.
   - **In-session branch** (default) — read the mode file and inject its full contents into the current session as a user message.
   - Done. Stop here.
3. **If zero or multiple files match**, fall through to the routing table below.

## Routing (all other requests)

Load only the one file needed for the request:

| Request | Load |
|---|---|
| Load, but the fast path above found no match or multiple candidates | [flows/load-fallback.md](flows/load-fallback.md) |
| List available modes | [flows/list.md](flows/list.md) |
| Create a new mode | [flows/create.md](flows/create.md) |
| Update an existing mode | [flows/update.md](flows/update.md) |
