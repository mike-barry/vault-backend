# Corpus Doc Flow

Owns the **corpus** of a project or area: the always-current *what/how* of the as-built system or subject. Unlike a planning doc — which is frozen and captures the *why/journey* — corpus docs are **living** and get updated as the subject evolves. (This doc type was formerly called a "design doc"; the concept is unchanged, the name is now cross-domain — it holds the durable, authored facts about a thing, whether that's a software system, a motorcycle, or a homelab box.)

Corpus docs are distinct from the top-level PARA `Resources/` folder: `Resources/` holds reference material for topics that span projects and areas (authored or external), while a project's or area's `Corpus/` holds the facts you **author and maintain** about its own subject.

The overall reference for a project or area is not one document. It is a **set of per-aspect docs**, each covering one facet of the subject (e.g. networking, storage, a service's data model, a bike's drivetrain). The work that a planning doc tracks either **updates** the aspect doc(s) it changed or **adds** a new aspect doc for genuinely new design.

This flow is reached two ways: directly ("document the design of X", "update the ref", "write the as-built doc", "reconcile the ref", "capture the facts about X") or as the close-out handoff from the planning flow.

## Corpus Layout

- Aspect docs live in the **`Corpus/` subfolder** of the project or area. Example: `Areas/<Area>/Corpus/Networking.md`, `Projects/<Project>/Corpus/Data-Model.md`.
- Each aspect doc is named `<Aspect>.md` in `Title-Case-With-Hyphens`, descriptive enough to identify the facet without opening it.
- The project or area's **folder note** is the index: its `nav.contents` frontmatter lists every aspect doc. There is no separate overview doc — the folder note is where agents already look.
- Discover the corpus by globbing `<project-or-area>/Corpus/*.md`.

## Aspect Doc Shape

An aspect doc describes the **current** state of one facet. It does not narrate history — that lives in the frozen planning docs it links back to.

| Section | Purpose |
|---------|---------|
| Frontmatter | `doc.created` + `doc.type: Corpus` — schema per [[Document-Conventions]]. No `doc.archived`: aspect docs are living and never move to `Archive/`. Plus an `agent.instructions` `use_skill:` entry routing edits through this skill (see [[#Reconcile the Corpus]]). |
| H1 title | The aspect name in Title Case (e.g. `# Networking`). A content note, so no `.md`-in-title. No other `agent.*`/`nav.*` frontmatter (unless a genuine intrinsic policy applies — see the `vault-agent-frontmatter` skill). |
| Intro paragraph | One paragraph: what facet this covers and where it fits in the subject. No heading. |
| `## Background` | *(Optional.)* The **provenance log** — the trail to the "why" behind the current design. A planning-doc change links the plan; an ad hoc change adds a dated one-line rationale (and a `vault-capture-chat` note link when the conversation is worth keeping). Entries are pointers to the *why*, never restatements of the *what*. Omit the section when no provenance exists yet, and omit any individual entry that would fail the litmus test below. |
| Body | The as-built facts, in H2/H3 sections as the facet needs. Written as present-tense current state. |

Keep the body **current-state only** — present-tense as-built, no dated "changed X to Y" history that restates the body. That is the "no changelog" rule, and it applies to the body alone.

The `## Background` section is the exception by design: it is a **provenance log**, not a changelog, and it is allowed to accumulate. The line between the two is what an entry carries — a Background entry points to the *why* (a plan link, a one-line rationale, a captured conversation); it never restates the *what* of the change, which already lives in the body.

**Litmus test — write an entry only if it survives this:** would a reader who has both `git log` and the current body still be missing the *why*? Git history already answers "what changed and when"; the body already answers "what's true now." An entry that just restates either of those in prose contributes nothing new and should be omitted. An entry earns its place only when it carries a reason, tradeoff, or rejected alternative that neither source captures — "X was changed" is not an entry; "X was changed because Y" is, and only when Y isn't already spelled out in the body itself.

When a ref update happens **without a planning doc** (an ad hoc change made directly in conversation), add a dated one-line rationale to `## Background` capturing why the change was made, **if** it clears the litmus test above. If the conversation holds rationale worth preserving, offer the chat-capture flow and link the saved note from the entry; if the user declines or the change is minor, the one-line rationale alone is enough. Only **substantive** changes are even candidates for an entry — apply the same durability gate as [[#When to Create or Update]]; trivial copyedits do not.

## When to Create or Update

The gate, applied before touching the corpus:

- Only record reference facts when the work leaves a **durable subject worth ongoing reference**. A one-off task with nothing lasting to document **skips** the corpus entirely.
- **This gate is about the subject, not the artifact.** A durable subject can still be mid-draft. The trigger for touching the corpus is **finalization or archiving of the work** — not the act of saving an in-progress artifact about that subject. A draft procedures doc, a half-written design note, or any WIP content belongs in `Inbox/` until it's finalized, even when its eventual home is a corpus aspect doc.
- **If you judge the work does not meet either half of the gate, confirm with the user before skipping.** State briefly why it looks like a skip and let them override - the user may know of durable facts worth capturing that aren't obvious from the work alone. Only skip once they agree.
- If the gate passes, decide per facet whether to update an existing aspect doc or add a new one (next section).

## Reconcile the Corpus

The core flow, run at a plan's close-out or on a direct request. "Reconcile" = bring the corpus in line with the current state the work actually produced.

1. **Identify the aspect(s)** the work touched. One change may span several facets.
2. **Match against the corpus.** Glob `<project-or-area>/Corpus/*.md` and find any aspect doc that already covers each facet.
3. **Decide per facet:**
   - **Covered** → **update in place.** Revise the body to the new current state, then add a `## Background` entry if it clears the [[#Aspect Doc Shape]] litmus test: link the planning doc if one drove the change, or a dated one-line rationale (plus optional captured-chat link) for an ad hoc change. If the doc predates the `use_skill:` convention, add it now.
   - **New facet** → **add** a new `Corpus/<Aspect>.md` using the [[#Aspect Doc Shape]], injecting its `use_skill:` entry by running `scripts/add-skill-directive.ps1 -DocPath <path> -When 'editing this file'`.
     Seed `## Background` the same way, subject to the same litmus test — plan link if one drove it, else a dated rationale line; omit if there is no provenance or the entry would just restate the body.
   - **Ambiguous** (spans several existing docs, or unclear whether it's a new facet) → **ask the user** rather than guessing how to slice it.
4. **Update the index.** Hand off to the `vault-agent-frontmatter` skill to add or update a `nav.contents` entry for each new or changed aspect doc in the project or area's folder note.
5. **Cross-link.** If a planning doc drove the change, confirm each touched aspect doc back-links it and that the planning doc references the corpus docs it produced. For an ad hoc update, confirm the `## Background` rationale entry is in place (and links the captured-chat note if one was saved).
