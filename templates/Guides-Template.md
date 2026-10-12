---
nav.contents:
  - link: "[[Vault-Guide]]"
    description: The bootstrap agent rules - navigation, folder notes, honoring agent.instructions
    load_when: always; loaded at session start rather than navigated to
  - link: "[[Vault-Organization]]"
    description: PARA placement, the standard subfolders, folder conventions, and manifest maintenance
    load_when: adding, moving, or removing a file or folder, or updating the manifest
  - link: "[[Document-Conventions]]"
    description: Doc types, titles, naming, and the doc.* frontmatter fields
    load_when: creating or significantly modifying any doc
  - link: "[[Frontmatter-Schema]]"
    description: The authoritative spec for the agent.* and nav.* frontmatter layer
    load_when: writing or validating agent-facing frontmatter
  - link: "[[Skill-Dev]]"
    description: Conventions for authoring and maintaining vault skills
    load_when: writing or changing a skill
---
# Guides.md - Agent Guide Docs

The guide docs this vault operates by. Each is a read-in-full destination: an agent loads the whole body rather than navigating within it.

These are the vault's own copies and are edited here. The `.claude/` submodule carries `-Template` counterparts that travel between vaults; changes worth sharing are reconciled back to them by hand.
