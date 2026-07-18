---
name: spawn-session
description: Launch a new Claude Code CLI session in a separate window. Use when the user says "spawn a new session", "open a new Claude window", "new Claude instance", "start another Claude", "open Claude in X directory", or wants a fresh Claude Code session running alongside the current one.
---

# Spawn Session

Open a new Claude Code CLI window as a detached process.

## Steps

1. **Resolve the target directory** — use the current working directory unless the user specified a path. Expand `~` and relative paths to absolute.

2. **Check for a mode** — if the user wants to load one or more vault modes into the new session, resolve each mode name against `Resources/Vault/Modes/Modes.md` (exact match first, then fuzzy/substring). Resolve each matched mode to its absolute file path (`Resources/Vault/Modes/Mode-<Name>.md`). Multiple modes are supported — each gets its own `--append-system-prompt-file` flag.

3. **Check for an initial prompt** — if the user wants to pre-seed the new session with a message, capture it.

4. **Launch based on platform:**

   **Windows (PowerShell):**

   On Windows, `claude` resolves to a `.ps1` file that `Start-Process` would open as a document. Use `claude.cmd` instead — it's the correct entry point for `Start-Process`:

   ```powershell
   # No mode, no prompt
   Start-Process "claude.cmd" -WorkingDirectory "<target-dir>"

   # With mode(s) — one --append-system-prompt-file per mode
   Start-Process "claude.cmd" -ArgumentList @(
       "--append-system-prompt-file", "<abs-path-to-Mode-X.md>",
       "--append-system-prompt-file", "<abs-path-to-Mode-Y.md>"
   ) -WorkingDirectory "<target-dir>"

   # With mode(s) and initial prompt
   Start-Process "claude.cmd" -ArgumentList @(
       "--append-system-prompt-file", "<abs-path-to-Mode-X.md>",
       '"<prompt>"'
   ) -WorkingDirectory "<target-dir>"
   ```

   **macOS / Linux (Bash):**
   ```bash
   # No mode, no prompt
   (cd "<target-dir>" && claude) &

   # With mode(s)
   (cd "<target-dir>" && claude --append-system-prompt-file "<abs-path-to-Mode-X.md>") &

   # With mode(s) and initial prompt
   (cd "<target-dir>" && claude --append-system-prompt-file "<abs-path-to-Mode-X.md>" "<prompt>") &
   ```

5. **Confirm** — tell the user the new session launched, in which directory, and which mode(s) were injected. Do not wait for it or track its output.

## Notes

- Launch only one instance unless the user explicitly asks for multiple.
- If the target directory doesn't exist, say so rather than creating it.
- Mode files live at `Resources/Vault/Modes/Mode-<Name>.md`. Use absolute paths when passing to `--append-system-prompt-file`.
- Modes are injected at the system-prompt level — they take effect from turn one, before any user message. This is preferable to loading them via `/vault-mode` after the session starts.
- Multiple modes stack — each `--append-system-prompt-file` appends in order. Personality modes (e.g. HAL-9000) should be listed before context modes so personality is established first.
- The new session is fully independent — it has no memory of this conversation.
