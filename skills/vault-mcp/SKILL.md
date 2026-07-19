---
name: vault-mcp
description: Troubleshoot and recover the vault MCP server connection — detect whether the server is up, start it, read its logs, and walk the recovery paths for a floored or disconnected session. Use when the vault MCP tools (mcp__vault__*) are missing from the session, a vault tool call fails with a connection, scope, or grant error, the server returns 503, or the user says "the vault server is down", "MCP tools aren't loading", "restart the vault server", or similar.
---

# Vault MCP

Goal: figure out why the vault MCP server isn't usable from this session, fix what an agent can fix, and tell the human plainly when only they can finish the recovery.

Script: `.claude/skills/vault-mcp/scripts/vault-mcp.ps1 -Action <Probe|Log|Start>`. Defaults: server repo `C:\Repos\vault-server`, port `5111`.

Auth background the diagnosis relies on: the client sends the committed, non-secret selector token (`Bearer vault-mcp-localhost-selector`, inlined in `.mcp.json` — nothing to set per machine), and the server binds it to the grant named by `appsettings.json`'s `LocalhostAuth:DefaultGrantId` (`admin` on dev machines, as a token-less named grant in `grants.json`). Localhost auth never 401s: a blank, unknown, or expired token floors to the built-in `minimum-access` grant — `health_check` and `request_elevation` still work, vault content doesn't.

## Steps

### 1. Connected path first

If the `mcp__vault__*` tools are loaded in this session, call `health_check` before anything else — it returns the server's own degradation detail. Then:

- `health_check` clean and the failing tool's error is specific to its arguments → the server and connection are fine; diagnose from that error.
- Vault-content tools fail with `not scoped to vault ...` or `Grant ... does not permit ...` while `health_check` works → the session is **floored to `minimum-access`**: the selector didn't resolve to the dev default. Verify `appsettings.json` has `LocalhostAuth:DefaultGrantId: admin` and `grants.json` carries the token-less named `admin` grant (`"named": true`); grant/config changes are startup-only, so after fixing, the human must restart the server and reconnect the client (see [[#Reconnecting is human-only]]). Don't try `request_elevation` as a workaround — the shipped approver auto-denies.

If the tools are absent, or calls fail with connection/transport errors, fall through to the script.

### 2. Probe

`-Action Probe` runs a tokenless `health_check` over raw HTTP (the fail-closed floor makes this work with no credential) and reports `ServerState`:

- **`Down`** (connection refused) → step 3.
- **`Up`** (200 with a health payload, echoed as `IsFatallyDegraded` / `ProblemCount` / problem lines) → the server is alive; if problems are listed, address those; otherwise the issue is client-side → step 4.
- **`Degraded`** (503 — fatally degraded; the body deliberately names no detail) → step 5.
- **`UpUnexpected` / `Unreachable`** → something is answering oddly or hanging; check the log (step 5) and report what you see.

### 3. Server down — start it

`-Action Start` launches the server via the repo's `run.ps1` (a detached `dotnet run` window — the current convenience mechanism) and polls until the probe answers.

- Comes up (`Up`) → the process is running, but this session's MCP client is still disconnected. Tell the human how to reconnect for their surface (see [[#Reconnecting is human-only]]); the agent cannot do this.
- Still down at timeout → `-Action Log` and report the newest log's errors verbatim.

### 4. Server up but tools missing — client-side diagnosis

There is no per-machine token to check anymore — the selector is committed in `.mcp.json`. With the server `Up` and clean, only two client-side causes remain, both human-only:

- The one-time project-scope `.mcp.json` approval was denied (a prior "deny" sticks until cleared — `claude mcp reset-project-choices` from a terminal resets it).
- The client just needs a reconnect after a server restart.

Walk the human through it per [[#Reconnecting is human-only]].

### 5. Degraded or odd — read the log

`-Action Log -ErrorsOnly` prints the newest `logs/vault-mcp-server-*.log` (one file per server start) filtered to Warning and above; drop `-ErrorsOnly` or raise `-Tail` for full context. Fatal config problems log at Error, per-entry skips (grant rows, vaults, tool scripts) at Warning. Report what the log says verbatim and propose the fix, but don't edit server config without confirming with the human.

### 6. Deep verification — E2E smoke test

`C:\Repos\vault-server\e2e-smoke.ps1` builds the server (Release), starts its own instance against the machine's real config, runs a fixed probe set (health, auth floor, elevation denial, attenuation, audit-log hygiene), and tears down. Use it after server code or config changes, or when diagnosis points at the deployment seam (config parse errors, grants problems) rather than the client connection. It refuses to run while port 5111 is occupied — never kill a running server to make room for it without confirming with the human first. On a red result, triage from the failing probe's detail line plus `-Action Log`; don't re-derive the probe logic in prose.

## Reconnecting is human-only

The agent cannot reconnect the MCP client; how the human does it depends on the surface:

- **Terminal CLI session**: run `/mcp`, select `vault`, and Reconnect (or Approve, if pending).
- **Claude Desktop app**: the CLI's `/mcp` server panel does not exist there — typing `/mcp` opens the third-party Connectors gallery, where project-scoped `.mcp.json` servers never appear. Each conversation is its own session and `.mcp.json` is read at session start, so **start a new conversation in the same project folder** — no app quit needed, and an existing conversation has no reload/reconnect affordance once the client's auto-reconnect attempts are exhausted. A previously-denied approval clears with `claude mcp reset-project-choices` from a terminal first.

## Honest limits

State these plainly instead of retrying in circles:

- The agent **can** start the server process.
- The agent **cannot** reconnect the MCP client — see [[#Reconnecting is human-only]] for what to tell the human.
- Grant and server-config changes are **startup-only** — after editing `grants.json` or `appsettings.json`, only a server restart (agent-doable) plus a client reconnect (human-only) makes them effective.
