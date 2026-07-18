# ConvertTo-OmiMarkdown.ps1
#
# Converts a single Omi conversation JSON file to the four-section vault transcript
# markdown format: Agent Instructions / Speaker Map / Correction Glossary / Transcript.
#
# Usage:
#   .\ConvertTo-OmiMarkdown.ps1 -JsonFile "path\to\<id>.json"
#   .\ConvertTo-OmiMarkdown.ps1 -JsonFile "path\to\<id>.json" -OutputFile "path\to\out.md"
#
# If -OutputFile is omitted the markdown is written to stdout.
# Fetch-OmiTranscripts.ps1 supplies -OutputFile and controls the output path.

param(
    [Parameter(Mandatory)][string]$JsonFile,
    [string]$OutputFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Format-Seconds([double]$TotalSeconds) {
    $s = [Math]::Max(0.0, $TotalSeconds)
    $h   = [int][Math]::Floor($s / 3600)
    $m   = [int][Math]::Floor(($s % 3600) / 60)
    $sec = [int][Math]::Floor($s % 60)
    "{0}:{1:D2}:{2:D2}" -f $h, $m, $sec
}

$Conv = Get-Content -Path $JsonFile -Raw -Encoding UTF8 | ConvertFrom-Json

$StartedAt  = [datetimeoffset]::Parse($Conv.started_at,  [cultureinfo]::InvariantCulture).ToUniversalTime()
$FinishedAt = [datetimeoffset]::Parse($Conv.finished_at, [cultureinfo]::InvariantCulture).ToUniversalTime()
$DurationMin = [int][Math]::Round(($FinishedAt - $StartedAt).TotalMinutes)

$S          = $Conv.structured
$Title      = if ($S.title)    { $S.title }    else { "(untitled)" }
$Category   = if ($S.category) { $S.category } else { "" }
$Overview   = if ($S.overview) { $S.overview } else { "" }
$FolderName = if ($Conv.folder_name) { $Conv.folder_name } else { "" }

$Address = if ($Conv.geolocation -and $Conv.geolocation.address) {
    $Conv.geolocation.address
} else { "" }

# Unique speakers in order of first appearance
$SeenSpeakers = [System.Collections.Generic.List[string]]::new()
foreach ($Seg in $Conv.transcript_segments) {
    if (-not $SeenSpeakers.Contains($Seg.speaker_name)) {
        $SeenSpeakers.Add($Seg.speaker_name)
    }
}

$Lines = [System.Collections.Generic.List[string]]::new()

$Lines.Add("# $Title")
$Lines.Add("")

# ── Agent Instructions ──────────────────────────────────────────────────────
$Lines.Add("## Agent Instructions")
$Lines.Add("")
$Lines.Add("Status: awaiting-first-pass")
$Lines.Add("Omi ID: $($Conv.id)")
$Lines.Add("Date: $($StartedAt.ToString('yyyy-MM-dd'))")
$Lines.Add("Time: $($StartedAt.ToString('HH:mm')) UTC")
$Lines.Add("Duration: $DurationMin min")
if ($Category)   { $Lines.Add("Category: $Category") }
if ($FolderName) { $Lines.Add("Omi Folder: $FolderName") }
if ($Address)    { $Lines.Add("Location: $Address") }
if ($Overview)   { $Lines.Add(""); $Lines.Add("**Omi summary:** $Overview") }
$Lines.Add("")

# ── Speaker Map ─────────────────────────────────────────────────────────────
$Lines.Add("## Speaker Map")
$Lines.Add("")
$Lines.Add("| Speaker Label | Real Name |")
$Lines.Add("|---|---|")
foreach ($Speaker in $SeenSpeakers) {
    $Lines.Add("| $Speaker | |")
}
$Lines.Add("")

# ── Correction Glossary ──────────────────────────────────────────────────────
$Lines.Add("## Correction Glossary")
$Lines.Add("")
$Lines.Add("| Garbled | Correct |")
$Lines.Add("|---|---|")
$Lines.Add("")

# ── Transcript ───────────────────────────────────────────────────────────────
$Lines.Add("## Transcript")
$Lines.Add("")
foreach ($Seg in $Conv.transcript_segments) {
    $Ts = Format-Seconds $Seg.start
    $Lines.Add("**$($Seg.speaker_name)** [$Ts]: $($Seg.text)")
}

$Markdown = $Lines -join "`n"

if ($OutputFile) {
    [System.IO.File]::WriteAllText(
        $OutputFile,
        $Markdown,
        [System.Text.Encoding]::UTF8
    )
} else {
    Write-Output $Markdown
}
