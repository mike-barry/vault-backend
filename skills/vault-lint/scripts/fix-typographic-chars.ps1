# Typographic character replacements:
# U+2013 En dash         -> -
# U+2014 Em dash         -> -
# U+2015 Horizontal bar  -> -
# U+2012 Figure dash     -> -
# U+201C Left dbl quote  -> "
# U+201D Right dbl quote -> "
# U+2018 Left sgl quote  -> '
# U+2019 Right sgl quote -> '
# U+2026 Ellipsis        -> ...
# U+00A0 Non-breaking sp -> (space)

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

$dashes   = [string][char]0x2013 + [char]0x2014 + [char]0x2015 + [char]0x2012
$ldquote  = [char]0x201C
$rdquote  = [char]0x201D
$lsquote  = [char]0x2018
$rsquote  = [char]0x2019
$ellipsis = [char]0x2026
$nbsp     = [char]0x00A0

Get-LintMarkdownFiles -PathOverride $PathOverride -VaultRootOverride $VaultRootOverride | ForEach-Object {
    $path = $_.FullName
    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $newContent = $content `
        -replace "[$dashes]", '-' `
        -replace "[$ldquote$rdquote]", '"' `
        -replace "[$lsquote$rsquote]", "'" `
        -replace "$ellipsis", '...' `
        -replace "$nbsp", ' '

    # Ordinal comparison: the default -ne is culture-sensitive and treats e.g.
    # an ellipsis as equal to '...' and a non-breaking space as equal to ' ',
    # which would mask exactly the changes this script makes.
    if (-not [string]::Equals($content, $newContent, [System.StringComparison]::Ordinal)) {
        if ($Update) {
            [System.IO.File]::WriteAllText($path, $newContent, $Utf8NoBom)
            Write-Host "Updated: $($_.Name)"
        } else {
            Write-Host "Would update: $($_.Name)"
            $counts = [ordered]@{
                'dashes'           = [regex]::Matches($content, "[$dashes]").Count
                'curly doubles'    = [regex]::Matches($content, "[$ldquote$rdquote]").Count
                'curly singles'    = [regex]::Matches($content, "[$lsquote$rsquote]").Count
                'ellipses'         = [regex]::Matches($content, [regex]::Escape($ellipsis)).Count
                'non-break spaces' = [regex]::Matches($content, [regex]::Escape($nbsp)).Count
            }
            foreach ($type in $counts.Keys) {
                if ($counts[$type] -gt 0) {
                    Write-Host "  $($type): $($counts[$type])"
                }
            }
        }
    }
}
