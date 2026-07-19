# unit-tests.ps1
# Direct tests for vault-mcp-core.ps1. Only the pure helpers are covered here;
# Probe/Start touch the live port and process state and are exercised manually.
# Test state is a plain temp folder (not vault files), so this overrides
# Reset-TestFolder with a temp-dir reset instead of the worktree helpers.

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')
. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-test-common.ps1')
. (Join-Path $PSScriptRoot 'vault-mcp-core.ps1')

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "vault-mcp-test-$(Get-Random)"
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Reset-TestFolder {
    if (Test-Path $testRoot) { Remove-Item -Recurse -Force $testRoot }
    New-Item -ItemType Directory -Path $testRoot | Out-Null
}

# ---------------------------------------------------------------------------
Write-Host "`nResolve-ProbeState:"

Run-Test 'classifies 200 as Up' {
    (Resolve-ProbeState -StatusCode 200) -eq 'Up'
}

Run-Test 'classifies 503 as Degraded' {
    (Resolve-ProbeState -StatusCode 503) -eq 'Degraded'
}

Run-Test 'classifies other statuses as UpUnexpected (localhost never 401s)' {
    (Resolve-ProbeState -StatusCode 401) -eq 'UpUnexpected' -and
    (Resolve-ProbeState -StatusCode 404) -eq 'UpUnexpected' -and
    (Resolve-ProbeState -StatusCode 405) -eq 'UpUnexpected'
}

# ---------------------------------------------------------------------------
Write-Host "`nConvertFrom-SseJson:"

Run-Test 'parses a single data line' {
    $json = ConvertFrom-SseJson -Body "event: message`ndata: {`"result`":{`"ok`":true}}`n"
    $json.result.ok -eq $true
}

Run-Test 'handles CRLF line endings and ignores non-data lines' {
    $json = ConvertFrom-SseJson -Body "event: message`r`ndata: {`"id`":3}`r`n`r`n"
    $json.id -eq 3
}

Run-Test 'rejoins a payload split across multiple data lines' {
    $json = ConvertFrom-SseJson -Body "data: {`"a`":`ndata: 1}"
    $json.a -eq 1
}

# ---------------------------------------------------------------------------
Write-Host "`nGet-NewestServerLog:"

Run-Test 'picks the newest log by filename sort' {
    New-TestFile 'vault-mcp-server-20260718-220957727.log' 'old'
    New-TestFile 'vault-mcp-server-20260719-103337525.log' 'newest'
    New-TestFile 'vault-mcp-server-20260719-094222394.log' 'mid'
    $log = Get-NewestServerLog -LogsDir $testRoot
    $log.Name -eq 'vault-mcp-server-20260719-103337525.log'
}

Run-Test 'ignores non-matching files' {
    New-TestFile 'vault-mcp-server-20260719-094222394.log' 'real'
    New-TestFile 'other-service-20260720-000000000.log' 'decoy'
    $log = Get-NewestServerLog -LogsDir $testRoot
    $log.Name -eq 'vault-mcp-server-20260719-094222394.log'
}

Run-Test 'returns null for an empty logs dir' {
    $null -eq (Get-NewestServerLog -LogsDir $testRoot)
}

Run-Test 'returns null for a missing logs dir' {
    $null -eq (Get-NewestServerLog -LogsDir (Join-Path $testRoot 'nope'))
}

# ---------------------------------------------------------------------------
Write-Host "`nGet-LogTail:"

Run-Test 'returns at most -Tail lines from the end' {
    New-TestFile 'a.log' ((1..10 | ForEach-Object { "line $_" }) -join "`n")
    $tail = Get-LogTail -Path (Join-Path $testRoot 'a.log') -Tail 3
    $tail.Count -eq 3 -and $tail[0] -eq 'line 8' -and $tail[2] -eq 'line 10'
}

Run-Test 'returns all lines when file is shorter than -Tail' {
    New-TestFile 'a.log' "one`ntwo"
    $tail = Get-LogTail -Path (Join-Path $testRoot 'a.log') -Tail 40
    $tail.Count -eq 2
}

Run-Test '-ErrorsOnly keeps only bracketed Warning-and-above lines' {
    $content = @(
        '2026-07-19 [Information] Cat: routine chatter'
        '2026-07-19 [Warning] Cat: grant row skipped'
        '2026-07-19 [Error] Cat: fatal config problem'
        '2026-07-19 [Information] Cat: message mentions Error but is not one'
    ) -join "`n"
    New-TestFile 'a.log' $content
    $tail = Get-LogTail -Path (Join-Path $testRoot 'a.log') -Tail 40 -ErrorsOnly
    $tail.Count -eq 2 -and $tail[0] -match 'Warning' -and $tail[1] -match 'Error'
}

Run-Test '-ErrorsOnly filters before the tail so problems are not pushed out' {
    $lines = @('2026-07-19 [Error] Cat: the real problem') + (1..50 | ForEach-Object { "2026-07-19 [Information] Cat: chatter $_" })
    New-TestFile 'a.log' ($lines -join "`n")
    $tail = Get-LogTail -Path (Join-Path $testRoot 'a.log') -Tail 5 -ErrorsOnly
    $tail.Count -eq 1 -and $tail[0] -match 'the real problem'
}

# ---------------------------------------------------------------------------
if (Test-Path $testRoot) { Remove-Item -Recurse -Force $testRoot }
Write-TestSummary
