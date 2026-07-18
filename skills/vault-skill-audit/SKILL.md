---
name: vault-skill-audit
description: Audit a Claude skill along four axes — visibility, deterministic-vs-non-deterministic steps, composability, and signal-to-noise — and report concrete findings. User-invoked only, never auto-fired.
disable-model-invocation: true
---
# Skill Audit

Audits one skill's `SKILL.md` (and any co-located scripts) against four axes and reports concrete, actionable findings. Report-only by default — fixes are applied only on confirmation. See [[Skill-Dev]] for the vault's skill structure, naming, and shared-script conventions this audit checks against.

## Resolve Target

- If a skill name was given as an argument, resolve it to `.claude/skills/<name>/SKILL.md`. If it doesn't exist, list the closest name matches and ask which one was meant.
- If no skill was specified, list the skills under `.claude/skills/` and ask the user which one to audit. Do not default to auditing all of them.
- Audits exactly one skill unless the user explicitly asks for more than one (e.g. "audit all skills", "audit vault-doc-archive and vault-doc-rename").

## Load

Read the target skill's `SKILL.md` in full. Read any co-located files it references (scripts, schema docs) as needed to judge determinism and composability — enough to see what's already scripted, not a full line-by-line review of script internals.

## Axis 1: Visibility

- **High-risk side effects** (writes/moves/deletes files, commits, pushes, sends messages, calls external APIs) → check whether `disable-model-invocation: true` is set. If it's missing, flag it as a candidate.
- **Pure background knowledge** the user would never `/run` directly (e.g. a skill only ever invoked programmatically by other skills) → check whether `user-invocable: false` is set. Flag if missing.
- Don't flag a skill that already carries the appropriate frontmatter. If it's unclear whether a side effect is "high-risk" or a skill is genuinely user-facing, ask rather than assume.

## Axis 2: Deterministic vs Non-Deterministic

- Walk each step in the skill body. Flag any step that is a fixed, repeatable transform (string manipulation, filename convention, frontmatter injection, wiki-link rewriting, date parsing, etc.) but is currently described as agent-performed prose rather than delegated to a script.
- A step already delegated to a co-located script is not a finding.
- Judgment steps — classification, routing, summarizing, drafting, confirming with the user — are correctly agent-owned and are not findings.
- For each flagged step, name the step and sketch what a script would take as input and produce as output.

## Axis 3: Composability

- Compare the skill's logic against other skills under `.claude/skills/`. Flag any step that duplicates logic another skill already owns (e.g. wiki-link rewriting, frontmatter writing, filename-convention checks).
- Suggest either handing off to the existing skill/script, or — if no shared implementation exists yet and the duplication is real — extracting one.
- A skill that already hands off to another skill for shared logic is not a finding, unless that hand-off is incomplete and duplicates the logic anyway.

### Script-Level Check

For any script owned by the audited skill (`.claude/skills/<skill>/scripts/*.ps1`), also evaluate at the function level against every file in `.claude/skills/_shared/`:

- **Duplication** — does a function reimplement something a `_shared` script already provides? Flag it and suggest calling the shared helper instead.
- **Promotion candidate** — does a function implement logic generic enough to be useful to other skills (not specific to this skill's domain)? Flag it as a promotion candidate. Use [[Skill-Dev]]'s *Where a Function Belongs* rule to name which `_shared` file it belongs in (a domain-scoped `vault-xxx.ps1`, or the domain-independent `vault-common.ps1`) — or whether a new domain file is warranted.

If a promotion finding is confirmed and applied, **ask the user before doing anything more** — the sweep goes outside the skill they asked to audit. Explain that the newly-promoted helper might benefit other skills' scripts and ask whether to sweep for candidates. Only after explicit approval, read every other skill's scripts for logic the helper could replace and report what you find as further composability findings. If declined, stop — do not read other skills' scripts on your own initiative.

Refactoring an existing script to call the shared version (rather than leaving it duplicated) is worth doing even though it touches working code. Per Apply below, propose the specific edit and get confirmation before making it — then follow up with full testing:

- Run the skill's own `unit-tests.ps1` (or equivalent) before and after the change.
- Add or update unit tests to cover the refactored path if the existing suite doesn't already exercise it.
- Do not report a script-level fix as applied until its tests are green.

## Axis 4: Signal-to-Noise

Agents authoring or editing skills tend to leave behind fluff: chatty phrasing, the same rule restated in more than one place, detail that doesn't change what the agent does, or "archeological" remnants — sentences describing a prior version of the step that no longer matches what the skill actually does after a later edit.

- **Repetition** — the same instruction or constraint stated in more than one place. Flag it and point to which instance to keep (usually the more specific/actionable one).
- **Stale remnants** — wording left over from before a change, now inconsistent with the current steps (e.g. still describing an old flow, an old field name, an old script that was since replaced). Flag it as a correctness issue, not just noise.
- **Irrelevant detail** — background, rationale, or examples that don't affect how the agent executes the step and aren't needed to make a judgment call correctly.
- **Do not over-trim.** Do not flag a sentence just because it's long or explanatory. Keep anything that carries a hidden constraint, a non-obvious "why," an edge case, or context a future agent needs to make the right judgment call. If it's unclear whether a passage is load-bearing or fluff, ask rather than cut — losing real context on a future run costs more than a slightly longer skill file.
- For each finding, quote or point to the specific passage, state what to cut or condense, and say why removing it doesn't lose anything the skill needs.

## Report

Present findings grouped by axis. For each finding, give the specific location (step or section name), what's wrong, and the concrete fix. If an axis has no findings, say so briefly rather than omitting it.

## Apply (on confirmation)

Ask whether to apply the findings. Handle each kind differently:

- **Frontmatter changes** (Axis 1) — low-risk, edit directly once confirmed.
- **Script extraction / hand-off changes** (Axis 2, Axis 3) — real implementation work; confirm scope with the user before writing any code, since a new script needs testing.

Before applying anything beyond a minor edit (a single frontmatter field, a small in-place tweak), offer to spin the proposed changes into a planning doc via the `vault-docs` skill instead of just diving in — this covers multi-step script extractions, new `_shared` files, or anything touched by the cross-skill sweep. Let the user choose: plan it first, or proceed directly.

Findings the user declines are left out of the response going forward — this is a one-time audit, not a tracked ticket log.
