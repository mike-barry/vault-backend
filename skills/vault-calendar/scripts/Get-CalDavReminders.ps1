# Get-CalDavReminders.ps1
#
# Proof-of-concept: list VTODO items (Reminders) from an iCloud calendar via CalDAV.
# Runs discovery (CalDavClient.ps1) to resolve the target calendar by name, then issues
# a REPORT calendar-query filtered to VTODO and parses the returned iCalendar text.
#
# Credential resolution: same as Test-CalDavDiscovery.ps1 (params, then Windows
# Credential Manager target "vault-calendar:icloud").
#
# Usage:
#   .\Get-CalDavReminders.ps1                       # defaults to the "Reminders" calendar
#   .\Get-CalDavReminders.ps1 -CalendarName "Work"   # any calendar that supports VTODO
#   .\Get-CalDavReminders.ps1 -IncludeCompleted

param(
    [string]$AppleId,
    [securestring]$AppPassword,
    [string]$CalendarName = "Reminders",
    [switch]$IncludeCompleted
)

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-credentials.ps1')
. (Join-Path $PSScriptRoot 'CalDavClient.ps1')

if (-not $AppleId -or -not $AppPassword) {
    $Stored = Get-StoredCredential -Target "vault-calendar:icloud"
    if ($Stored) {
        if (-not $AppleId)     { $AppleId     = $Stored.UserName }
        if (-not $AppPassword) { $AppPassword = $Stored.Password }
    }
}

if (-not $AppleId -or -not $AppPassword) {
    Write-Error "No iCloud credentials found. Run .\Set-CalDavCredential.ps1 once to store them in Windows Credential Manager, or pass -AppleId/-AppPassword."
    exit 1
}

$AuthHeader = Get-CalDavAuthHeader -AppleId $AppleId -AppPassword $AppPassword

# Unfolds RFC 5545 folded lines (continuation lines start with a single space or tab)
# and extracts BEGIN:VTODO...END:VTODO blocks as flat property-name/value objects.
function ConvertFrom-VTodoText {
    param([Parameter(Mandatory)][string]$IcsText)

    $Unfolded = $IcsText -replace "(`r`n|`n|`r)[ `t]", ''
    $Lines = $Unfolded -split "`r`n|`n|`r"

    $Results = @()
    $Current = $null
    foreach ($Line in $Lines) {
        if ($Line -eq 'BEGIN:VTODO') { $Current = @{}; continue }
        if ($Line -eq 'END:VTODO') {
            if ($Current) { $Results += [PSCustomObject]$Current }
            $Current = $null
            continue
        }
        if ($null -eq $Current) { continue }
        # NAME(;PARAMS)?:VALUE — property names are uppercase letters/digits/hyphens only.
        if ($Line -match '^([A-Z0-9-]+)(;[^:]*)?:(.*)$') {
            $Current[$Matches[1]] = $Matches[3]
        }
    }
    $Results
}

# Best-effort iCalendar DATE/DATE-TIME -> [datetime]; returns the raw string unchanged
# if it doesn't match a recognized form (e.g. still carries a TZID parameter's offset).
function ConvertFrom-VTodoDate {
    param([string]$Value)
    if (-not $Value) { return $null }
    if ($Value -match '^\d{8}T\d{6}Z$') {
        return [datetime]::ParseExact($Value, 'yyyyMMddTHHmmssZ', [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
    }
    if ($Value -match '^\d{8}$') {
        return [datetime]::ParseExact($Value, 'yyyyMMdd', [cultureinfo]::InvariantCulture)
    }
    return $Value
}

Write-Host "Discovering calendars..."
$Calendars = Get-CalDavCalendars -AuthHeader $AuthHeader
$Target = $Calendars | Where-Object { $_.DisplayName -like "*$CalendarName*" -and $_.Components -match 'VTODO' } | Select-Object -First 1
if (-not $Target) {
    $Available = ($Calendars | ForEach-Object { "$($_.DisplayName) [$($_.Components)]" }) -join ', '
    throw "No calendar matching '$CalendarName' with VTODO support found. Available: $Available"
}
Write-Host "  target: $($Target.DisplayName) ($($Target.Href))"

Write-Host "Fetching VTODO items..."
$ReportBody = @"
<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:getetag />
    <c:calendar-data />
  </d:prop>
  <c:filter>
    <c:comp-filter name="VCALENDAR">
      <c:comp-filter name="VTODO" />
    </c:comp-filter>
  </c:filter>
</c:calendar-query>
"@
$Result = Invoke-CalDavRequest -Uri $Target.Href -Method REPORT -Body $ReportBody -AuthHeader $AuthHeader -Depth 1
$Xml = Get-CalDavResponseXml $Result

$Reminders = @()
foreach ($Resp in (Select-Xml -Xml $Xml -Namespace $Script:CalDavNs -XPath '//d:response').Node) {
    $DataNode = (Select-Xml -Xml $Resp -Namespace $Script:CalDavNs -XPath './/c:calendar-data').Node
    if (-not $DataNode) { continue }
    foreach ($Todo in (ConvertFrom-VTodoText -IcsText $DataNode.InnerText)) {
        $Reminders += [PSCustomObject]@{
            Summary   = $Todo.SUMMARY
            Status    = if ($Todo.STATUS) { $Todo.STATUS } else { 'NEEDS-ACTION' }
            Due       = ConvertFrom-VTodoDate $Todo.DUE
            Completed = ConvertFrom-VTodoDate $Todo.COMPLETED
            Uid       = $Todo.UID
        }
    }
}

if (-not $IncludeCompleted) {
    $Reminders = $Reminders | Where-Object { $_.Status -ne 'COMPLETED' }
}

Write-Host ""
Write-Host "Found $($Reminders.Count) reminder(s) in '$($Target.DisplayName)'$(if (-not $IncludeCompleted) { ' (excluding completed)' }):"
$Reminders | Sort-Object Due | Format-Table -AutoSize
