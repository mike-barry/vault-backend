---
name: vault-transcript-fetch
description: Pull new conversation transcripts from the Omi.me servers via the Omi REST API. NOT YET IMPLEMENTED — currently a proof-of-concept fetch script only. Do not invoke for normal use.
---

# vault-transcript-fetch

Pull new conversation transcripts from the Omi.me servers via the Omi REST API.

## Status: Not Yet Implemented

This skill is a stub. Only a proof-of-concept fetch script exists today; the full skill workflow (markdown rendering, classification, filing into the vault) is not built.

- **POC script:** [scripts/Fetch-OmiTranscripts.ps1](scripts/Fetch-OmiTranscripts.ps1) — authenticates against the Omi REST API, pulls new conversations with transcript segments, and writes each as a raw JSON file to `.vault/omi-transcripts/`. Uses a `finished_at` timestamp cursor (`omi-last-fetch.txt`) for dedup across runs. Credentials (`omi-secrets.ps1`, gitignored) and the cursor live in the per-vault state folder `.vault/state/vault-transcript-fetch/`. Downloaded transcript JSON and rendered markdown live under `.vault/omi-transcripts/` at the vault root.

To run the POC manually:

```powershell
# Relies on the gitignored omi-secrets.ps1 in .vault/state/vault-transcript-fetch/ for the key, or set it explicitly:
$env:OMI_API_KEY = "omi_dev_xxxx"   # developer key from the Omi app
.\.claude\skills\vault-transcript-fetch\scripts\Fetch-OmiTranscripts.ps1
```

## Background

Design and conventions for the broader transcript pipeline live in [[Plan-Transcript-Ingest-And-Summarization]]. Key confirmed facts:

- **API:** `GET https://api.omi.me/v1/dev/user/conversations?include_transcript=true`
- **Auth:** `Authorization: Bearer omi_dev_...` (developer key; `omi_mcp_` keys do not work)
- **Pagination:** `limit`/`offset`; **dedup:** `start_date` cursor on `finished_at`
- **Rate limits:** 100 req/min per key, 10,000 req/day per user

## TODO before this is usable

- [ ] Confirm the `transcript_segments` field shape from a real API response
- [ ] Render JSON conversations to the structured markdown transcript file format
- [ ] Classify and file transcripts into the correct project/area `Inbox/`
- [ ] Resolve credentials from an `omi-config.json` in this skill folder in addition to the env var
- [ ] Decide trigger model (scheduled routine vs. manual invocation)
