param(
    # Vault-relative folder to scope the scan (e.g. 'Areas/Personal'). When omitted, all
    # configured include folders are scanned.
    [string]$PathOverride,
    # Vault root directory. Auto-resolved from the script location when not specified; pass
    # explicitly for non-default locations such as a test worktree.
    [string]$VaultRootOverride
)

. "$PSScriptRoot\lint-common.ps1"
$vaultRoot = if ($VaultRootOverride) { $VaultRootOverride } else { Get-VaultRoot $PSScriptRoot }

$violations = @()

Get-LintMarkdownFiles -PathOverride $PathOverride -VaultRootOverride $vaultRoot | ForEach-Object {
    $baseName = $_.BaseName
    $relPath  = $_.FullName.Substring($vaultRoot.Length)
    $issues   = @()

    if ($baseName -match ' ') {
        $issues += 'contains spaces'
    }
    if ($baseName -match '_') {
        $issues += 'contains underscores'
    }
    # Check Title-Case: each hyphen-separated segment must start with uppercase.
    # Skip all-caps names (e.g. README, CLAUDE) and date-prefixed names (e.g. 2024-01-15).
    # Use case-SENSITIVE operators (-cmatch/-cnotmatch); the default -match is
    # case-insensitive and would treat every capitalized segment as lowercase.
    if ($baseName -cnotmatch '^[A-Z0-9]+$' -and $baseName -notmatch '^\d{4}-\d{2}') {
        # A lowercase-starting segment is a violation unless it's a known minor
        # word (to, of, and, ...) appearing somewhere other than the first segment.
        $segments    = $baseName -split '-'
        $badSegments = for ($i = 0; $i -lt $segments.Count; $i++) {
            $seg = $segments[$i]
            if ($seg -cmatch '^[a-z]' -and
                -not ($i -gt 0 -and $titleLowercaseWords -contains $seg) -and
                -not ($titleCaseExceptions -contains $seg)) {
                $seg
            }
        }
        if ($badSegments) {
            $issues += "not Title-Case (segments: $($badSegments -join ', '))"
        }
    }

    if ($issues.Count -gt 0) {
        $violations += [PSCustomObject]@{ File = $relPath; Issues = ($issues -join '; ') }
    }
}

if ($violations.Count -eq 0) {
    Write-Host "No filename convention violations found."
} else {
    foreach ($v in $violations) {
        Write-Host "Violation: $($v.File)"
        Write-Host "  -> $($v.Issues)"
    }
    Write-Host ""
    Write-Host "$($violations.Count) filename violation(s) found."
}
