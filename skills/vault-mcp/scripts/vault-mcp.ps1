# vault-mcp.ps1
# Diagnostics and recovery mechanics for the vault-mcp skill. Each -Action is a
# deterministic check or launch; interpreting the results (what to tell the
# human, when only a reconnect will do) stays in the skill's prose.
#
# Usage:
#   .\vault-mcp.ps1 -Action Probe
#   .\vault-mcp.ps1 -Action Log [-Tail <n>] [-ErrorsOnly]
#   .\vault-mcp.ps1 -Action Start [-TimeoutSec <n>]
#
# -ServerRepo defaults to C:\Repos\vault-mcp-server; -Port to 5111.

param(
    [Parameter(Mandatory)][ValidateSet('Probe', 'Log', 'Start')]
    [string]$Action,
    [string]$ServerRepo = 'C:\Repos\vault-mcp-server',
    [int]$Port = 5111,
    [int]$Tail = 40,
    [switch]$ErrorsOnly,
    [int]$TimeoutSec = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'vault-mcp-core.ps1')

function Write-KV {
    param([string]$Key, $Value)
    Write-Host "${Key}: $Value"
}

# Tokenless health_check tools/call against the MCP endpoint. No Authorization
# header on purpose: localhost auth floors a missing token to the built-in
# minimum-access grant, which may still call health_check - so a bare probe
# both proves the server is up and returns its degradation detail. Returns
# @{ State; StatusCode; Health } (Health parsed from the payload when Up).
# Connection refused (SocketException anywhere in the chain) means Down; any
# other transport failure (e.g. timeout) is Unreachable.
function Invoke-ServerProbe {
    $body = '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"health_check","arguments":{}}}'
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:$Port/mcp" -Method Post `
            -Headers @{ Accept = 'application/json, text/event-stream' } `
            -ContentType 'application/json' -Body $body -SkipHttpErrorCheck -TimeoutSec 5
        $out = @{ State = (Resolve-ProbeState -StatusCode $resp.StatusCode); StatusCode = [int]$resp.StatusCode; Health = $null }
        if ($out.State -eq 'Up') {
            $rpc = ConvertFrom-SseJson -Body $resp.Content
            $text = @($rpc.result.content) | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
            if ($text) { $out.Health = $text.text | ConvertFrom-Json }
        }
        return $out
    } catch {
        $ex = $_.Exception
        while ($ex) {
            if ($ex -is [System.Net.Sockets.SocketException]) {
                return @{ State = 'Down'; StatusCode = $null; Health = $null }
            }
            $ex = $ex.InnerException
        }
        return @{ State = 'Unreachable'; StatusCode = $null; Health = $null }
    }
}

function Write-ProbeReport {
    param([hashtable]$Probe)
    Write-KV 'ServerState' $Probe.State
    Write-KV 'StatusCode' ($Probe.StatusCode ?? '')
    if ($Probe.Health) {
        Write-KV 'IsFatallyDegraded' $Probe.Health.isFatallyDegraded
        Write-KV 'ConfiguredVaults' ($Probe.Health.vaults.configured -join ', ')
        $problems = @($Probe.Health.problems)
        Write-KV 'ProblemCount' $problems.Count
        foreach ($p in $problems) {
            Write-Host "  [$($p.severity)] $($p.source): $($p.detail)"
        }
    }
}

switch ($Action) {

    # -------------------------------------------------------------------
    'Probe' {
        Write-ProbeReport -Probe (Invoke-ServerProbe)
        exit 0
    }

    # -------------------------------------------------------------------
    'Log' {
        $log = Get-NewestServerLog -LogsDir (Join-Path $ServerRepo 'logs')
        if (-not $log) {
            Write-Host "No vault-mcp-server-*.log files found under $ServerRepo\logs"
            exit 1
        }
        Write-KV 'LogFile' $log.FullName
        Write-KV 'LastWriteTime' $log.LastWriteTime
        Write-Host '---'
        Get-LogTail -Path $log.FullName -Tail $Tail -ErrorsOnly:$ErrorsOnly | ForEach-Object { Write-Host $_ }
        exit 0
    }

    # -------------------------------------------------------------------
    'Start' {
        $probe = Invoke-ServerProbe
        if ($probe.State -ne 'Down') {
            Write-KV 'ServerState' $probe.State
            Write-Host 'Server is not down - not starting a second instance.'
            exit 0
        }
        $runScript = Join-Path $ServerRepo 'run.ps1'
        if (-not (Test-Path $runScript)) {
            Write-Error "run.ps1 not found at $runScript"
            exit 1
        }
        # run.ps1 itself Start-Process-es a detached pwsh window running
        # `dotnet run`, so this call returns immediately.
        & $runScript
        Write-Host "Launched $runScript - waiting for the port to answer..."

        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        do {
            Start-Sleep -Seconds 1
            $probe = Invoke-ServerProbe
        } while ($probe.State -eq 'Down' -and (Get-Date) -lt $deadline)

        Write-ProbeReport -Probe $probe
        if ($probe.State -eq 'Down') {
            Write-Host "Server did not come up within $TimeoutSec seconds - check the newest log (-Action Log)."
            exit 1
        }
        exit 0
    }
}
