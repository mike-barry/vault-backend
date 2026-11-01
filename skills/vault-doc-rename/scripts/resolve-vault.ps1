# resolve-vault.ps1
# Names the vault CLI's registered vault for this repo, so a rename's `vault move --vault <name>`
# lands in the clone being worked in rather than the CLI's configured default vault. Reads the
# registry the CLI itself reads: vault.settings.json beside vault.exe, whose VaultsConfigPath
# (default vaults.json beside it) resolves against the settings file's own folder.
#
# Usage:
#   .\resolve-vault.ps1 [-VaultRootOverride <path>] [-SettingsPath <vault.settings.json>]
#
# Output: one JSON object { Vault, Path, Default } on stdout. Exits 1 with the reason on stderr when
# vault.exe or its registry cannot be found, or when no registered vault has this repo's path.

param(
    [string]$VaultRootOverride,
    [string]$SettingsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-common.ps1')

function Get-NormalPath {
    param(
        # Any absolute path, either separator, with or without a trailing one.
        [Parameter(Mandatory)][string]$Path
    )
    return [System.IO.Path]::GetFullPath($Path).Replace('\', '/').TrimEnd('/')
}

$vaultRoot = if ($VaultRootOverride) { Format-VaultRoot $VaultRootOverride } else { Get-VaultRoot $PSScriptRoot }

if (-not $SettingsPath) {
    $exe = Get-Command vault -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) {
        Write-Error 'vault.exe is not on PATH'
        exit 1
    }
    $SettingsPath = Join-Path (Split-Path $exe.Source) 'vault.settings.json'
}
$settingsDir = Split-Path $SettingsPath

# An absent settings file or setting leaves the registry at its default, beside the executable.
$vaultsRel = 'vaults.json'
if (Test-Path $SettingsPath) {
    $settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    if ($settings.PSObject.Properties['VaultsConfigPath'] -and $settings.VaultsConfigPath) {
        $vaultsRel = $settings.VaultsConfigPath
    }
}
$vaultsPath = [System.IO.Path]::GetFullPath($vaultsRel, $settingsDir)
if (-not (Test-Path $vaultsPath)) {
    Write-Error "Vault registry not found: $vaultsPath"
    exit 1
}

$registry = Get-Content $vaultsPath -Raw | ConvertFrom-Json
$root = Get-NormalPath $vaultRoot
$match = $registry.vaults.PSObject.Properties | Where-Object {
    (Get-NormalPath $_.Value.path) -eq $root
} | Select-Object -First 1

if (-not $match) {
    Write-Error "No vault in $vaultsPath has path $root. Register this clone there, or rename the doc by hand"
    exit 1
}

[pscustomobject]@{
    Vault   = $match.Name
    Path    = $root
    Default = ($match.Name -eq $registry.default_vault)
} | ConvertTo-Json -Compress
