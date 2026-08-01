---
doc.created: 2026-06-16
---
# Vault-Organization.md - Vault Structural Guidelines

Rules for organizing content and maintaining the vault's folder structure.

## PARA Placement

- **Projects/** - work with a defined finish line; archive the folder when the project is complete
- **Areas/** - ongoing responsibilities with no finish line
- **Resources/** - reference material for **topics that span projects and areas**, or that don't belong to a specific project or area; authored or external. Distinct from a project's or area's `Corpus/` subfolder: `Resources/` is organized by **topic** and is not scoped to any one project or area, while `Corpus/` holds the **authored, actively-maintained** reference scoped to that specific project's or area's own subject (see the subfolder table below)
- **Archive/** - completed projects and frozen records; managed by the `vault-project-archive` skill
- **Inbox/** - catch-all for content that doesn't fit any existing project or area; triage from here into the appropriate project or area

## Project and Area Subfolders

Each project and area has three standard subfolders, always present:

| Subfolder  | Purpose                                                                                                           | Skill                   |
| ---------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `Inbox/`   | All active **ephemeral** docs: planning docs, idea docs, chat captures, reading captures, meeting notes, ad-hoc content | `vault-docs`            |
| `Corpus/`  | **Durable** authored reference corpus for this project's or area's own subject                                    | `vault-docs` (corpus flow) |
| `Archive/` | Completed ephemeral docs, moved from Inbox/                                                                       | `vault-doc-archive`     |

Ephemeral docs have a lifecycle endpoint - they live in `Inbox/` while active and move to `Archive/` when complete. Durable docs (corpus docs, folder notes, guide docs, `Resources/` content, working files like `Tasks.md`) persist indefinitely and are never archived.

Placement rules:

- New ingested content (chat captures, reading notes, meeting summaries), planning docs (`Plan-*.md`), idea docs (`Idea-*.md`), and ad-hoc notes all go in `Inbox/`. The type prefix in the filename is the discriminator.
- Corpus docs go in `Corpus/` and are updated in place - they never get archived. `Corpus/` is for material **authored and maintained here** about the project's or area's own subject; reference material on topics that span multiple projects or areas belongs in the top-level PARA `Resources/` instead.
- Folder notes, guide docs, and working infrastructure files (e.g. `Tasks.md`) are durable - update them in place; delete when superseded.
- Use `vault-doc-archive` to move any ephemeral doc to `Archive/`. It applies the correct filename convention and injects provenance frontmatter. `vault-docs` (plan and idea flows) call it automatically at close-out; it is also user-invocable directly.

Ad-hoc subfolders may be created inside `Inbox/` at any time (e.g. `Inbox/Hold/`). Skills always write new files to `Inbox/` root but search it recursively when finding or updating existing files.

The local `Archive/` is distinct from the top-level PARA `Archive/`, which holds whole completed projects and is managed by `vault-project-archive`.

## Folder Conventions

- Use `Title-Case-With-Hyphens` for folder names
- Create a folder note when a folder has more than a few files or needs agent instructions
- Folder notes are named after their folder (e.g. `Vault.md` inside `Resources/Vault/`)
- When two folder notes share a filename, use path-qualified wiki-links to distinguish them (e.g. `[[Resources/Vault]]` vs `[[Areas/Vault-Dev/Vault-Dev]]`)

## Maintaining the Vault Manifest

Update the structure tree in [[Vault-Manifest]] when:

- A folder is added, moved, renamed, or deleted
- A folder's purpose or contents change enough that its brief description needs updating

Keep descriptions in the structure tree short - one phrase per line.
