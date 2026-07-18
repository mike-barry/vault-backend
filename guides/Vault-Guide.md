---
doc.created: 2026-05-31
---
# Vault-Guide.md - Vault Guide for AI Agents

Agent rules for operating in a personal markdown knowledge base. The vault's own structure and areas are described in its [[Vault-Manifest]].

## Agent Instructions

- Wiki-links (`[[Note-Name]]`) reference files by name only - use a glob (`**/Note-Name.md`) to locate them
- **Navigate by [[Vault-Manifest]] and note frontmatter first.** Follow the structure there and the `nav.contents` / `nav.see_also` entries in note frontmatter, loading an entry's note or listed folder when its `load_when` condition matches the conversation; glob and grep the vault only as fallbacks when frontmatter routing does not resolve the need
- **Always load the folder note before responding when a conversation touches a project or area** - each folder has its own note named after it (e.g. `Areas/Outdoors/Outdoors.md`); resolve via glob `**/FolderName.md`
- Read [[Document-Conventions]] before creating or significantly modifying any doc
- Read [[Vault-Organization]] before adding, moving, or removing any file or folder, placing content within a project or area, or updating [[Vault-Manifest]]
- **Honor `agent.instructions` on any note you touch.** A plain string entry is a revisable navigation hint; a `pinned:` entry (the user's own binding, hands-off rule, e.g. sensitivity / no-exfil) and a `use_skill:` entry (a binding directive to consult or route through the named skill under its stated `when:` condition) apply no matter how you reached the note - never edit or drop them
- Answer questions from the vault; if the answer isn't here, say so rather than guessing
