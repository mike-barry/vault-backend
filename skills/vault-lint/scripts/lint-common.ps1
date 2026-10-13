# Shared configuration and helpers for vault-lint scripts.
# Dot-source this file: . (Join-Path $_skillDir 'scripts' 'lint-common.ps1')

$_skillDir = if ($env:CLAUDE_SKILL_DIR) { $env:CLAUDE_SKILL_DIR } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $_skillDir '..' '_shared' 'vault-common.ps1')

# .claude\guides is the backend guides tier - vault-convention content that lints like any
# other; the rest of .claude (skills, settings) is harness contract and stays out of scope.
$includeFolders = @('Archive', 'Areas', 'Projects', 'Resources', '.claude\guides')
$excludeFiles   = @('Document-Conventions.md', 'Document-Conventions-Template.md')
# Vault-relative directory paths to skip entirely (and their subfolders). Templates
# contain literal placeholders like [[Note-Name]] that would otherwise be flagged.
$excludePaths   = @('Resources\Vault\Templates')

# Minor words that may stay lowercase in Title-Case filenames (articles, short
# conjunctions and prepositions) - except as the first segment. Used by the
# filename-conventions check so names like Road-to-Hana-Planning pass.
$titleLowercaseWords = @(
    'a', 'an', 'and', 'as', 'at', 'but', 'by', 'for', 'from', 'if', 'in', 'into',
    'nor', 'of', 'off', 'on', 'onto', 'or', 'per', 'so', 'the', 'to', 'up', 'via',
    'vs', 'with', 'yet'
)

# Brand names, proper nouns, and file-extension references whose internal capitalization
# deviates from Title-Case (e.g. iCloud starts with lowercase 'i'; 'md' stays lowercase in a
# filename like Reading-...-CLAUDE-md-... that's literally referencing "CLAUDE.md"). Segments
# matching any entry returned here are exempt from the Title-Case check.
#
# Vault state rather than a hardcoded array: the list lives at
# .vault/state/vault-lint/filename-exceptions.txt so one file serves both this skill and the
# server's lint_suppressions tool, which is the only write path to it. A missing file degrades
# to no exceptions, matching how check-broken-wikilinks.ps1 treats a missing ignore list.
# Resolution is deferred to a function because the vault root is not known at dot-source time -
# callers pass -VaultRootOverride after resolving it, the same shape Get-LintMarkdownFiles uses.
function Get-TitleCaseExceptions {
    param(
        # Vault root directory. Auto-resolved from the script location when not specified.
        [string]$VaultRootOverride
    )
    if (-not $VaultRootOverride) { $VaultRootOverride = Get-VaultRoot $PSScriptRoot }
    $exceptionsFile = Join-Path $VaultRootOverride '.vault\state\vault-lint\filename-exceptions.txt'
    if (-not (Test-Path $exceptionsFile)) { return @() }
    @([System.IO.File]::ReadAllLines($exceptionsFile) |
        ForEach-Object { ($_ -split '#', 2)[0].Trim() } |
        Where-Object { $_ -ne '' })
}

# Strips fenced code blocks and inline code spans from markdown content, so checks that
# scan for [[wikilinks]] or similar prose-only patterns don't match literal syntax shown as
# an example inside backticks. Fenced blocks are stripped first (multiline, ```/~~~ delimited).
# Inline spans are stripped per-paragraph (blank-line-bounded) rather than across the whole
# file, so an unterminated backtick run can't hunt for its closing match arbitrarily far away
# and swallow unrelated text in between.
function Remove-CodeSpansAndFences {
    param([string]$Content)
    $stripped = [regex]::Replace($Content, '(?ms)^(```|~~~).*?^\1\s*$', '')
    $sb = New-Object System.Text.StringBuilder
    foreach ($para in [regex]::Split($stripped, '(?:\r?\n){2,}')) {
        [void]$sb.Append([regex]::Replace($para, '(?s)(`+)(?:(?!\1).)*?\1', ''))
        [void]$sb.Append("`n`n")
    }
    return $sb.ToString()
}

# Enumerate markdown files using lint-specific include/exclude rules.
# Pass -PathOverride (vault-relative) to scan a single folder instead — used by tests
# and ad-hoc runs; the include-folder list is bypassed but file/path exclusions still apply.
function Get-LintMarkdownFiles {
    param(
        # Vault-relative folder to scope the scan (e.g. 'Areas/Personal'). When omitted, all
        # configured include folders are scanned.
        [string]$PathOverride,
        # Vault root directory. Auto-resolved from the script location when not specified.
        [string]$VaultRootOverride
    )
    if (-not $VaultRootOverride) { $VaultRootOverride = Get-VaultRoot $PSScriptRoot }
    Get-VaultMarkdownFiles -VaultRoot $VaultRootOverride -PathOverride $PathOverride `
        -IncludeFolders $includeFolders -ExcludeFiles $excludeFiles -ExcludePaths $excludePaths
}
