# claude-auth-relay.ps1
# Human-in-the-loop relay for renewing the Claude Code login on a machine with
# no browser at hand. `claude auth login` prints a sign-in URL and then waits
# for a code on stdin, even with no terminal attached, so the relay runs it as
# a hidden background driver with piped stdio and moves text between that
# process and the human: the URL out, the code in. The human approves the
# sign-in on their own device; the relay never completes a login by itself.
#
# Usage:
#   .\claude-auth-relay.ps1 -Action Start           launch the driver, print the URL
#   .\claude-auth-relay.ps1 -Action Url             print the URL again
#   .\claude-auth-relay.ps1 -Action Code -Code <c>  hand the pasted code to the login
#   .\claude-auth-relay.ps1 -Action Status          phase, timestamps, last output, expiry
#   .\claude-auth-relay.ps1 -Action Abort           kill a driver and its login process
#
# -Action Drive is internal: it is what Start launches in the hidden window.
# State lives in ~\.claude-auth-relay (state.json, login.log, code.txt).

param(
    [Parameter(Mandatory)][ValidateSet('Start', 'Url', 'Code', 'Status', 'Abort', 'Drive')]
    [string]$Action,
    [string]$Code,
    [int]$TimeoutSec = 900,
    [int]$WaitSec = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'claude-auth-core.ps1')

$stateDir = Get-RelayStateDir
$statePath = Join-Path $stateDir 'state.json'
$codePath = Join-Path $stateDir 'code.txt'
$logPath = Join-Path $stateDir 'login.log'
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }

function Write-KV { param([string]$Key, $Value) Write-Host "${Key}: $Value" }

function Get-State { Read-RelayState -Path $statePath }

function Get-Phase {
    $s = Get-State
    if ($null -eq $s) { return 'idle' }
    Resolve-RelayPhase -State $s -DriverAlive (Test-ProcessAlive (Get-Prop $s 'driverPid'))
}

# Poll until the phase is one of $Phases, or any non-in-flight phase appears
# (the driver finished some other way), or $Seconds pass.
function Wait-ForPhase {
    param([string[]]$Phases, [int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $phase = Get-Phase
        if ($phase -in $Phases -or -not (Test-RelayInFlight $phase)) { return $phase }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return (Get-Phase)
}

function Show-Status {
    $s = Get-State
    Write-KV 'Phase' (Get-Phase)
    if ($s) {
        Write-KV 'StartedAt' (Get-Prop $s 'startedAt')
        Write-KV 'Url' $(if (Get-Prop $s 'url') { 'available' } else { 'none' })
        Write-KV 'ExitCode' (Get-Prop $s 'exitCode')
        Write-KV 'FinishedAt' (Get-Prop $s 'finishedAt')
        Write-KV 'Message' (Get-Prop $s 'message')
    }
    $credPath = Get-ClaudeCredentialPath
    $exp = Get-CredentialExpiry -Json $(if (Test-Path $credPath) { Get-Content $credPath -Raw } else { '' })
    Write-KV 'DaysRemaining' $(if ($exp.Found) { $exp.DaysRemaining } else { 'no credential' })
}

function Show-Url {
    $url = Get-Prop (Get-State) 'url'
    Write-KV 'Url' $(if ($url) { $url } else { 'none' })
}

# ---------------------------------------------------------------------------
# Driver: runs in the hidden window Start launches. Owns the login process for
# its whole life and records progress in state.json for the other actions.
function Invoke-Drive {
    $state = @{
        phase = 'starting'; driverPid = $PID; loginPid = $null
        startedAt = (Get-Date).ToString('o'); url = $null
        exitCode = $null; finishedAt = $null; message = $null
    }
    Write-RelayState -Path $statePath -State $state
    if (Test-Path $codePath) { Remove-Item $codePath -Force }

    $credPath = Get-ClaudeCredentialPath
    $credBefore = if (Test-Path $credPath) { (Get-Item $credPath).LastWriteTimeUtc } else { [datetime]::MinValue }

    $out = [Text.StringBuilder]::new()
    $err = [Text.StringBuilder]::new()

    function Finish([string]$Phase, [string]$Message, $ExitCode) {
        $state.phase = $Phase; $state.message = $Message; $state.exitCode = $ExitCode
        $state.finishedAt = (Get-Date).ToString('o')
        Write-RelayState -Path $statePath -State $state
        $log = "--- stdout`r`n" + (Remove-AnsiEscapes $out.ToString()) + "`r`n--- stderr`r`n" + (Remove-AnsiEscapes $err.ToString())
        [IO.File]::WriteAllText($logPath, $log, [Text.UTF8Encoding]::new($false))
    }

    try {
        $claude = (Get-Command claude -ErrorAction Stop).Source
    } catch {
        Finish 'failed' 'claude is not on PATH' $null
        return
    }

    $psi = [Diagnostics.ProcessStartInfo]::new($claude)
    $psi.Arguments = 'auth login'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $state.loginPid = $proc.Id
    Write-RelayState -Path $statePath -State $state

    # Chunked async reads, polled, so a prompt that never ends in a newline
    # still lands in the buffer and nothing blocks on ReadLine.
    $outBuf = [char[]]::new(4096); $errBuf = [char[]]::new(4096)
    $script:outTask = $proc.StandardOutput.ReadAsync($outBuf, 0, $outBuf.Length)
    $script:errTask = $proc.StandardError.ReadAsync($errBuf, 0, $errBuf.Length)
    function Pump {
        while ($script:outTask.IsCompleted) {
            $n = $script:outTask.Result
            if ($n -le 0) { break }
            [void]$out.Append($outBuf, 0, $n)
            $script:outTask = $proc.StandardOutput.ReadAsync($outBuf, 0, $outBuf.Length)
        }
        while ($script:errTask.IsCompleted) {
            $n = $script:errTask.Result
            if ($n -le 0) { break }
            [void]$err.Append($errBuf, 0, $n)
            $script:errTask = $proc.StandardError.ReadAsync($errBuf, 0, $errBuf.Length)
        }
    }
    function Get-AllOutput { Get-LastOutputLine ($out.ToString() + "`n" + $err.ToString()) }

    # 1. Wait for the URL.
    $deadline = (Get-Date).AddSeconds(60)
    $url = $null
    while (-not $url -and (Get-Date) -lt $deadline -and -not $proc.HasExited) {
        Pump
        $url = Find-OAuthUrl $out.ToString()
        if (-not $url) { Start-Sleep -Milliseconds 250 }
    }
    Pump
    if (-not $url) {
        $exit = if ($proc.HasExited) { $proc.ExitCode } else { $proc.Kill(); $null }
        Finish 'failed' ('no sign-in URL printed: ' + (Get-AllOutput)) $exit
        return
    }
    $state.url = $url; $state.phase = 'awaiting-approval'
    Write-RelayState -Path $statePath -State $state

    # 2. Wait for the human's code to arrive via code.txt.
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not (Test-Path $codePath) -and (Get-Date) -lt $deadline -and -not $proc.HasExited) {
        Pump
        Start-Sleep -Seconds 1
    }
    Pump
    if ($proc.HasExited) {
        Finish 'failed' ('login exited before a code was supplied: ' + (Get-AllOutput)) $proc.ExitCode
        return
    }
    if (-not (Test-Path $codePath)) {
        $proc.Kill()
        Finish 'failed' "no code supplied within $TimeoutSec s" $null
        return
    }
    $code = (Get-Content $codePath -Raw).Trim()
    Remove-Item $codePath -Force
    $state.phase = 'submitting'
    Write-RelayState -Path $statePath -State $state

    # 3. Hand the code over and wait for the login to finish.
    $proc.StandardInput.WriteLine($code)
    $proc.StandardInput.Flush()
    $deadline = (Get-Date).AddSeconds(120)
    while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
        Pump
        Start-Sleep -Milliseconds 500
    }
    if (-not $proc.HasExited) {
        $proc.Kill()
        Finish 'failed' 'login did not finish within 120 s of the code' $null
        return
    }
    $proc.WaitForExit()
    Pump
    $credAfter = if (Test-Path $credPath) { (Get-Item $credPath).LastWriteTimeUtc } else { [datetime]::MinValue }
    $refreshed = $credAfter -gt $credBefore
    $last = Get-AllOutput
    if ($proc.ExitCode -eq 0 -and $refreshed) {
        Finish 'done' $last 0
    } else {
        $credState = if ($refreshed) { 'rewritten' } else { 'unchanged' }
        Finish 'failed' "exit $($proc.ExitCode), credential ${credState}: $last" $proc.ExitCode
    }
}

# ---------------------------------------------------------------------------
switch ($Action) {
    'Drive' { Invoke-Drive }

    'Start' {
        $phase = Get-Phase
        if (Test-RelayInFlight $phase) {
            Write-KV 'Result' 'AlreadyRunning'
            Show-Url
            Show-Status
            break
        }
        if (Test-Path $codePath) { Remove-Item $codePath -Force }
        $startedAt = (Get-Date).ToString('o')
        $pwsh = (Get-Process -Id $PID).Path
        $driverArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
            '-File', $PSCommandPath, '-Action', 'Drive', '-TimeoutSec', $TimeoutSec)
        $driver = Start-Process -FilePath $pwsh -ArgumentList $driverArgs -WindowStyle Hidden -PassThru
        # Placeholder so Get-Phase sees a live driver until the driver writes
        # its own state a moment later.
        Write-RelayState -Path $statePath -State @{ phase = 'starting'; driverPid = $driver.Id; startedAt = $startedAt; url = $null }
        $phase = Wait-ForPhase -Phases @('awaiting-approval') -Seconds $WaitSec
        Write-KV 'Result' $(if ($phase -eq 'awaiting-approval') { 'Started' } else { 'NotStarted' })
        Show-Url
        Show-Status
    }

    'Url' {
        $phase = Wait-ForPhase -Phases @('awaiting-approval') -Seconds $WaitSec
        Show-Url
        Write-KV 'Phase' $phase
    }

    'Code' {
        if ([string]::IsNullOrWhiteSpace($Code)) { throw '-Code is required' }
        $phase = Get-Phase
        if ($phase -ne 'awaiting-approval') {
            Write-KV 'Result' 'NotAwaitingCode'
            Show-Status
            exit 1
        }
        [IO.File]::WriteAllText($codePath, $Code.Trim(), [Text.UTF8Encoding]::new($false))
        $phase = Wait-ForPhase -Phases @('done', 'failed') -Seconds $WaitSec
        $result = switch ($phase) { 'done' { 'LoggedIn' } 'failed' { 'Failed' } default { 'Pending' } }
        Write-KV 'Result' $result
        Show-Status
        if ($phase -eq 'failed') { exit 1 }
    }

    'Status' { Show-Status }

    'Abort' {
        $s = Get-State
        foreach ($key in 'loginPid', 'driverPid') {
            $id = Get-Prop $s $key
            if (Test-ProcessAlive $id) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
        }
        if (Test-Path $codePath) { Remove-Item $codePath -Force }
        if ($s) {
            Write-RelayState -Path $statePath -State @{
                phase = 'aborted'; driverPid = $null; startedAt = (Get-Prop $s 'startedAt'); url = $null
                finishedAt = (Get-Date).ToString('o'); message = 'aborted by request'
            }
        }
        Write-KV 'Result' 'Aborted'
        Show-Status
    }
}
