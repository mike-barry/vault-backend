---
name: vault-claude-auth
description: Check how long the Claude Code login has left and relay a renewal through the human when the machine has no browser at hand. Use when the user says "renew the login", "re-auth Claude", "how long until the login expires", "the session says the token is expiring", or when a scheduled session needs the days-to-expiry figure for its monitoring push.
---

# Claude Auth

Goal: keep the Claude Code login on an always-on machine from lapsing unnoticed, and when it needs renewing, move the sign-in URL and the code between the human and `claude auth login` without ever completing the login on the human's behalf.

Scripts, Windows only for now (the Linux tmux form arrives with `nixbot1`). Call them by absolute path with this exact shape, which is what the permission rule in `.claude/settings.local.json` matches:

```powershell
pwsh -NoProfile -File C:/Repos/vault-primary/.claude/skills/vault-claude-auth/scripts/claude-auth-expiry.ps1 [-Json]
pwsh -NoProfile -File C:/Repos/vault-primary/.claude/skills/vault-claude-auth/scripts/claude-auth-relay.ps1 -Action <Start|Url|Code|Status|Abort> [-Code <code>]
```

## Background

The claude.ai login holds two tokens. The access token renews itself; the refresh token is the real deadline, roughly eight weeks, and once it lapses every session fails until someone logs in again. `claude auth login` prints a sign-in URL and then waits for a code on stdin, and it does so even with no terminal attached, which is what lets the relay drive it from a hidden process. `/login` does not work inside a Remote Control session, so the relay is the path from the phone.

## Expiry

`claude-auth-expiry.ps1` prints `Status`, `DaysRemaining`, and the two expiry timestamps, reading only those fields. `-Json` emits one object for a monitoring push. Exit 2 means no credential file or no claude.ai OAuth block in it. It never prints a token; do not read the credential file any other way.

## Renewal Relay

Each action is a separate call, so the flow survives the agent's turns ending between steps. State lives in `~\.claude-auth-relay`.

1. **`-Action Start`** launches a hidden driver that runs the login and prints the sign-in `Url` once it appears, normally within seconds. `Result: AlreadyRunning` means a relay is already waiting; use its URL. `NotStarted` means the URL never appeared; see the `Message` line and `~\.claude-auth-relay\login.log`.
2. **Hand the URL to the human verbatim.** They open it on a device where they are already signed in to claude.ai, approve, and get a code back.
3. **`-Action Code -Code <pasted code>`** passes the code to the waiting login. `Result: LoggedIn` is the only success: the login exited cleanly and the credential file was rewritten. `Failed` carries the login's last line in `Message`. `Pending` means it is still working; call `-Action Status` again shortly. `NotAwaitingCode` means nothing is waiting, so go back to step 1.
4. Report the new `DaysRemaining` from the output.

The driver gives the human 15 minutes for step 2 and then exits as `failed`; `-Action Url` reprints the URL meanwhile, and `-Action Abort` kills a relay that should not continue.

The human performs every step that proves presence. Never open the URL, fetch it, or try to obtain the code any way other than the human pasting it into the conversation. Never type a guessed or reused code.

## When the relay cannot help

If `Start` keeps failing, or the login rejects the code twice, stop and tell the human to RDP in and run `claude auth login` in a terminal. Whether a running session picks up a renewed credential, or only the next launch does, is not yet established; after a successful relay, say so and suggest the next scheduled session as the point where it is certain.
