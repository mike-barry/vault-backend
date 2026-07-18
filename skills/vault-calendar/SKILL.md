---
name: vault-calendar
description: Read and write Apple (iCloud) Calendar events via CalDAV. NOT YET IMPLEMENTED — currently a proof-of-concept discovery script only. Do not invoke for normal use.
---

# vault-calendar

General-purpose read/write access to iCloud Calendar (`VEVENT`) across multiple calendars (Work, Personal, Family) via CalDAV. Reminders (`VTODO`) is explicitly out of scope - see [[Plan-Vault-Calendar-Skill]].

## Status: Not Yet Implemented

This skill is a stub. CalDAV discovery and credential storage work against a real account; event retrieve/filter/insert/update are not built yet. Design lives in [[Plan-Vault-Calendar-Skill]].

- **POC scripts:** [scripts/CalDavClient.ps1](scripts/CalDavClient.ps1) (shared PROPFIND/REPORT + discovery plumbing), [scripts/Test-CalDavDiscovery.ps1](scripts/Test-CalDavDiscovery.ps1) (lists calendars). [scripts/Get-CalDavReminders.ps1](scripts/Get-CalDavReminders.ps1) is kept for reference only - it works, but documents that iCloud only ever returns Apple's migration-notice placeholders instead of real reminders via CalDAV, which is why Reminders is out of scope for this skill.
- **Credentials** are stored in Windows Credential Manager (target `vault-calendar:icloud`), read via a shared P/Invoke wrapper — [_shared/vault-credentials.ps1](../_shared/vault-credentials.ps1), reusable by any skill needing OS-level credential storage — rather than a gitignored secrets file or a third-party module. Reads are silent (DPAPI, tied to the Windows user account), so this works for unattended/scheduled use too. Unit tests: [_shared/tests/vault-credentials.unit-tests.ps1](../_shared/tests/vault-credentials.unit-tests.ps1).

Run once per machine to store your app-specific password (from appleid.apple.com):

```powershell
.\.claude\skills\vault-calendar\scripts\Set-CalDavCredential.ps1
```

Then run the discovery POC:

```powershell
.\.claude\skills\vault-calendar\scripts\Test-CalDavDiscovery.ps1
```

## TODO before this is usable

- [ ] Implement retrieve/list, filter, insert, update (upsert by UID) for calendar events (`VEVENT`)
- [ ] Wire the Outlook sync's write step to call this skill's insert/update against the "Work" calendar
