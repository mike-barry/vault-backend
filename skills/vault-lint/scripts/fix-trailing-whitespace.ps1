param(
    # Apply changes to disk. Without this switch the script reports what would change
    # without modifying any files.
    [switch]$Update,
    # Vault-relative folder to scope the scan (e.g. 'Areas/Personal'). When omitted, all
    # configured include folders are scanned.
    [string]$PathOverride,
    # Vault root directory. Auto-resolved from the script location when not specified; pass
    # explicitly for non-default locations such as a test worktree.
    [string]$VaultRootOverride
)

. "$PSScriptRoot\lint-common.ps1"

Get-LintMarkdownFiles -PathOverride $PathOverride -VaultRootOverride $VaultRootOverride | ForEach-Object {
    $path    = $_.FullName
    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $newContent = [regex]::Replace($content, '[ \t]+(?=\r?\n|$)', '')

    # Ordinal comparison: the default -ne is culture-sensitive and can treat
    # byte-level whitespace differences as equal, masking real changes.
    if (-not [string]::Equals($content, $newContent, [System.StringComparison]::Ordinal)) {
        if ($Update) {
            [System.IO.File]::WriteAllText($path, $newContent, $Utf8NoBom)
            Write-Host "Updated: $($_.Name)"
        } else {
            $count = [regex]::Matches($content, '[ \t]+(?=\r?\n|$)').Count
            Write-Host "Would update: $($_.Name) ($count line(s))"
        }
    }
}
