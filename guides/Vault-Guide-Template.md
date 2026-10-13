---
doc.created: 2026-05-31
---
# Vault-Guide.md - Vault Guide for AI Agents

Agent rules for operating in a markdown knowledge base.

## Agent Instructions

- Wiki-links (`[[Note-Name]]`) reference files by name only - use a glob (`**/Note-Name.md`) to locate them
- **Navigate by [[Vault-Manifest]] and note frontmatter first.** Follow the structure there and the `nav.contents` / `nav.see_also` entries in note frontmatter, loading an entry's note or listed folder when its `load_when` condition matches the conversation; glob and grep the vault only as fallbacks when frontmatter routing does not resolve the need
- **Always load the folder note before responding when a conversation touches a project or area** - each folder has its own note named after it (e.g. `Areas/Outdoors/Outdoors.md`); resolve via glob `**/FolderName.md`
- Read [[Document-Conventions]] before creating or significantly modifying any doc
- Read [[Vault-Organization]] before adding, moving, or removing any file or folder, placing content within a project or area, or updating [[Vault-Manifest]]
- **Honor `agent.instructions` on any note you touch.** A plain string entry is a revisable navigation hint; a `pinned:` entry (the user's own binding, hands-off rule, e.g. sensitivity / no-exfil) and a `use_skill:` entry (a binding directive to consult or route through the named skill under its stated `when:` condition) apply no matter how you reached the note - never edit or drop them
- **Line endings are handled for you.** This repo normalizes them through `.gitattributes` and a `pre-commit` hook. Git prints `warning: ... CRLF will be replaced by LF` when staging, which is expected and requires no action. Do not check or attempt to fix line endings
- Answer questions from the vault; if the answer isn't here, say so rather than guessing
- Keep responses focused and brief. Keep caveats short and spend the response on the answer itself; when asked to explain something, give a high-level summary unless depth is requested
- Before your first tool call, say in one sentence what you're about to do. While working, give a brief update only when you find something important or change direction. When you finish, lead with the outcome - the first sentence answers "what happened" or "what did you find", with detail after it
