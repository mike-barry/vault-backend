# Hard-Wrap Fix

Detects hard-wrapped (fixed-width) prose paragraphs and list items and joins them back into single lines, without disturbing frontmatter, tables, code fences (including mermaid), blockquotes/callouts, headings, or `[[wikilinks]]`.

This step is **preview-only until the user confirms**, same pattern as the other lint steps, but treat it more cautiously: the script is newer and has only been validated against a subset of the vault, not swept vault-wide.

1. **Preview.** Scope to a folder if the user named one; otherwise run vault-wide.

   ```powershell
   pwsh .claude/skills/vault-lint/scripts/fix-hard-wrap.ps1
   pwsh .claude/skills/vault-lint/scripts/fix-hard-wrap.ps1 -PathOverride "Areas/Vault-Dev/Corpus"
   ```

   Output is per-file counts only (auto-fixable / flagged-for-review line counts) — no block content. Show the raw output to the user.

2. **Inspect on request.** If the user wants to see the actual before/after for a flagged file:

   ```powershell
   pwsh .claude/skills/vault-lint/scripts/fix-hard-wrap.ps1 -InspectFile "path/to/File.md"
   ```

   Auto-fixable blocks show `before`/`after` text; flagged blocks show the reason (`unbalanced code span`, `unbalanced wikilink`, `unbalanced embed link`, `break inside embed link`). Flagged blocks are never auto-joined — they need manual review.

3. **Apply only on explicit confirmation.**

   ```powershell
   pwsh .claude/skills/vault-lint/scripts/fix-hard-wrap.ps1 -Update
   ```

4. **Review the diff yourself** (`git diff`) rather than assuming the corruption-safety checks caught everything — check wikilinks, tables, frontmatter, and code spans are intact.

A line only folds into the one before it when that previous line is near-full-width (`Test-IsFullWidthLine`, gated on the `$MinFullLineLength` constant in the script, currently 70 characters) — a genuinely hard-wrapped line lands close to its wrapping tool's column on every line but the last, while an intentionally short standalone line (a definition-list field, a short name line followed by an already-long unwrapped line) does not. This is what keeps adjacent short lines like `**Item1:** blah` / `**Item2:** blah` from being folded together.

A second, independent boundary catches the case length alone can't: an incoming line matching the bold-label prefix (`**Label:** value`, `Test-IsBoldLabelLine`) never folds into the running block, no matter how long the preceding line is. Two adjacent bold-label lines are independent record fields, not a wrapped pair, even when the first line's value is a long-but-standalone sentence that happens to clear the length gate on its own merits (e.g. `**Mike Dixon:** Previously with Duane Arnold in design engineering, helping with PPC piece` followed by `**Erik Sorensen:** Responsible for implementation`). A genuine wrap's continuation line is always plain prose, never a new bold-label opener, so this rule can't suppress a real wrap.

A third, independent boundary covers a standalone markdown image reference (`![alt](url)` as the entire line, `Test-IsImageEmbedLine`): it never folds into the running block either, including inside a list item whose continuation indentation and length would otherwise pass the existing checks. This catches a numbered list step's instruction text absorbing a screenshot embed on the next line (e.g. a step followed by `   ![image.png](/.attachments/....png)`) — a genuine wrap's continuation is never *only* an image reference, so this rule can't suppress a real wrap either.

**Known residual gap:** the length check is still a heuristic outside the bold-label case, so a narrow gray zone remains (roughly 67-81 characters in this vault's observed content) where an unusually long intentional short *non-bold-label* line, or an unusually short genuine wrap line, could still be misjudged. This is content-safe either way (no dropped/changed words, no broken syntax) but could still flatten an author-intentional line break, or leave a genuine wrap unjoined. Flag it to the user if you see it in a diff, but don't treat it as a corruption finding. Tune `$MinFullLineLength` in `fix-hard-wrap.ps1` if real content shows the threshold needs adjusting.
