# vault-mcp-core.ps1
# Pure helpers for the vault-mcp skill. Deterministic and unit-testable - no
# network calls, process launches, or environment reads here; those live in
# vault-mcp.ps1.

Set-StrictMode -Version Latest

# Classify the HTTP status of a tokenless health_check POST against the MCP
# endpoint. Localhost auth never 401s - a missing token floors to the built-in
# minimum-access grant, which may still call health_check - so 200 with a
# payload is the healthy answer. 503 is the fatally-degraded gate (detail is in
# the file log, never the body). Anything else is up but answering unexpectedly.
function Resolve-ProbeState {
    param([Parameter(Mandatory)][int]$StatusCode)
    switch ($StatusCode) {
        200 { 'Up' }
        503 { 'Degraded' }
        default { 'UpUnexpected' }
    }
}

# Extract the JSON payload from a streamable-HTTP MCP response body: the server
# answers as SSE, so the JSON-RPC envelope sits on "data:" lines that must be
# stripped (and rejoined, for a payload split across several) before parsing.
function ConvertFrom-SseJson {
    param([Parameter(Mandatory)][string]$Body)
    $dataLines = ($Body -split "`r?`n") |
        Where-Object { $_ -like 'data:*' } |
        ForEach-Object { $_.Substring(5).TrimStart() }
    return ($dataLines -join "`n") | ConvertFrom-Json
}

# Newest server log file in $LogsDir, or $null if the directory or any
# matching file is missing. Filenames embed the start timestamp
# (vault-mcp-server-{yyyyMMdd-HHmmssfff}.log), so name order is time order.
function Get-NewestServerLog {
    param([Parameter(Mandatory)][string]$LogsDir)
    if (-not (Test-Path $LogsDir)) { return $null }
    Get-ChildItem -Path $LogsDir -Filter 'vault-mcp-server-*.log' -File |
        Sort-Object Name -Descending | Select-Object -First 1
}

# Last $Tail lines of a log file. -ErrorsOnly keeps only lines at Warning or
# above (the file logger writes bracketed levels: [Warning], [Error],
# [Critical]); the filter runs before the tail so problems aren't pushed out
# by later Information chatter.
function Get-LogTail {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$Tail = 40,
        [switch]$ErrorsOnly
    )
    $lines = @(Get-Content -Path $Path)
    if ($ErrorsOnly) {
        $lines = @($lines | Where-Object { $_ -match '\[(Warning|Error|Critical|Fatal)\]' })
    }
    if ($lines.Count -gt $Tail) { $lines = $lines[-$Tail..-1] }
    return ,@($lines)
}
