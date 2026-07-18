# Fetch-OmiTranscripts.ps1
#
# Retrieves new conversations (with transcript segments) from the Omi REST API.
# Uses a timestamp cursor (omi-last-fetch.txt) so each run only fetches conversations
# that finished after the previous run.
#
# For each new conversation: saves raw JSON to .vault\omi-transcripts\json\ (dedup
# artifact and raw archive), then calls ConvertTo-OmiMarkdown.ps1 to render the
# four-section vault markdown file to .vault\omi-transcripts\.
#
# Credential resolution (in order): -ApiKey param, $env:OMI_API_KEY, then the gitignored
# omi-secrets.ps1 in .vault\state\vault-transcript-fetch\ (which sets $env:OMI_API_KEY
# when dot-sourced).
#
# Per-vault state lives under .vault\state\vault-transcript-fetch\ at the vault root:
# credentials (omi-secrets.ps1, gitignored) and the fetch cursor (omi-last-fetch.txt,
# tracked). Downloaded transcript JSON (omi-transcripts\json\) and rendered markdown
# (omi-transcripts\) live under .vault\ at the vault root.
#
# Usage:
#   # Option A: rely on the gitignored omi-secrets.ps1 in .vault\state\vault-transcript-fetch\
#   .\Fetch-OmiTranscripts.ps1
#
#   # Option B: supply the key explicitly
#   $env:OMI_API_KEY = "omi_dev_xxxx"   # developer key from the Omi app; omi_mcp_ keys do NOT work
#   .\Fetch-OmiTranscripts.ps1
#
# Params:
#   -ApiKey            Omi developer API key (defaults to $env:OMI_API_KEY)
#   -OutputDir         Directory to write markdown files (default: .vault\omi-transcripts)
#   -StateFile         Path to the cursor file storing last-fetched finished_at (default: .vault\state\vault-transcript-fetch\omi-last-fetch.txt)
#   -CursorBufferHours Subtract this many hours from the saved cursor to cover in-flight conversations (default: 1)

param(
    [string]$ApiKey            = $env:OMI_API_KEY,
    [string]$OutputDir         = "",   # resolved below to .vault\omi-transcripts under the vault root
    [string]$StateFile         = "",   # resolved below to .vault\state\vault-transcript-fetch\omi-last-fetch.txt
    [int]   $CursorBufferHours = 1
)

# Shared vault helpers (Get-VaultRoot, etc.).
$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-common.ps1')

$ConverterScript = Join-Path $PSScriptRoot 'ConvertTo-OmiMarkdown.ps1'

function Get-TitleSlug([string]$Title) {
    $slug = $Title -replace '[^\w\s-]', '' -replace '\s+', '-' -replace '-{2,}', '-'
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd('-') }
    $slug
}

$VaultRoot = Get-VaultRoot -StartPath $PSScriptRoot

# Fall back to the gitignored per-vault secrets file if no key was supplied.
if (-not $ApiKey) {
    $SecretsFile = Join-Path $VaultRoot ".vault\state\vault-transcript-fetch\omi-secrets.ps1"
    if (Test-Path $SecretsFile) {
        . $SecretsFile
        $ApiKey = $env:OMI_API_KEY
    }
}

if (-not $OutputDir) { $OutputDir = Join-Path $VaultRoot ".vault\omi-transcripts" }
if (-not $StateFile) { $StateFile = Join-Path $VaultRoot ".vault\state\vault-transcript-fetch\omi-last-fetch.txt" }
$JsonDir = Join-Path $OutputDir "json"

if (-not $ApiKey) {
    Write-Error "No API key provided. Set `$env:OMI_API_KEY or pass -ApiKey."
    exit 1
}

$BaseUrl = "https://api.omi.me/v1/dev/user/conversations"
$Headers = @{ Authorization = "Bearer $ApiKey" }

# Load last-fetched cursor as a UTC instant. Parse culture-invariantly so a value written
# on any locale round-trips, and normalize to UTC so the start_date we send is unambiguous.
# Subtract the buffer to re-query conversations that were in-flight on the last run (the
# on-disk id check below skips re-writing any that come back).
$RawCursor = if (Test-Path $StateFile) { (Get-Content $StateFile -Raw).Trim() } else { $null }
$CursorUtc = if ($RawCursor) {
    ([datetimeoffset]::Parse($RawCursor, [cultureinfo]::InvariantCulture)).ToUniversalTime()
} else { $null }
$StartDate = if ($CursorUtc) {
    $CursorUtc.AddHours(-$CursorBufferHours).ToString("o")
} else { $null }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path $JsonDir   | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $StateFile) | Out-Null

$Offset       = 0
$Limit        = 25
$NewestUtc    = $CursorUtc
$TotalFetched = 0

Write-Host "Starting fetch. Cursor: $($StartDate ?? '(all time)')"

do {
    $Query = "limit=$Limit&offset=$Offset&include_transcript=true"
    if ($StartDate) { $Query += "&start_date=$([Uri]::EscapeDataString($StartDate))" }

    try {
        $Conversations = Invoke-RestMethod -Uri "$BaseUrl`?$Query" -Headers $Headers -Method Get
    } catch {
        Write-Error "API call failed (offset=$Offset): $_"
        break
    }

    if (-not $Conversations -or $Conversations.Count -eq 0) { break }

    foreach ($Conv in $Conversations) {
        $Id       = $Conv.id
        $JsonFile = Join-Path $JsonDir "$Id.json"

        if (-not (Test-Path $JsonFile)) {
            # Save raw JSON as the dedup artifact and raw archive.
            $Conv | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFile -Encoding UTF8

            # Derive a human-readable markdown filename: YYYY-MM-DD-Title-Slug.md
            $DateStr  = ([datetimeoffset]$Conv.started_at).ToUniversalTime().ToString("yyyy-MM-dd")
            $Title    = if ($Conv.structured.title) { $Conv.structured.title } else { $Id }
            $MdFile   = Join-Path $OutputDir "$DateStr-$(Get-TitleSlug $Title).md"

            & $ConverterScript -JsonFile $JsonFile -OutputFile $MdFile
            Write-Host "  Saved: $($MdFile | Split-Path -Leaf)"
        } else {
            Write-Host "  Skip:  $Id  (already on disk)"
        }

        if ($Conv.finished_at) {
            $FinUtc = ([datetimeoffset]$Conv.finished_at).ToUniversalTime()
            if ($null -eq $NewestUtc -or $FinUtc -gt $NewestUtc) { $NewestUtc = $FinUtc }
        }
    }

    $TotalFetched += $Conversations.Count
    $Offset       += $Limit

} while ($Conversations.Count -eq $Limit)

if ($NewestUtc -and ($null -eq $CursorUtc -or $NewestUtc -gt $CursorUtc)) {
    $Stamp = $NewestUtc.ToString("o")
    Set-Content -Path $StateFile -Value $Stamp -Encoding UTF8
    Write-Host "Cursor updated: $Stamp"
}

Write-Host "Done. $TotalFetched conversation(s) retrieved this run."
