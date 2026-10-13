# README.md - New-Vault Scaffold Templates

Seed files for standing up a new vault on this backend. Each `*-Template.md` is copied to its contract path with the `-Template` suffix stripped; `plumbing/` is copied to the vault root as-is.

| Template | Destination |
|---|---|
| `Vault-Manifest-Template.md` | `Vault-Manifest.md` |
| `Areas-Template.md` | `Areas/Areas.md` |
| `Projects-Template.md` | `Projects/Projects.md` |
| `Archive-Template.md` | `Archive/Archive.md` |
| `Resources-Template.md` | `Resources/Resources.md` |
| `Vault-Template.md` | `Resources/Vault/Vault.md` |
| `Guides-Template.md` | `Resources/Vault/Guides/Guides.md` |
| `Modes-Template.md` | `Resources/Vault/Modes/Modes.md` |
| `plumbing/.gitignore`, `.gitattributes`, `.githooks/` | vault root; then `git config core.hooksPath .githooks` |

The guide docs themselves come from `../guides/*-Template.md`, copied the same way into `Resources/Vault/Guides/`.

Like the guides, these are starting points: the copies in a vault are that vault's own and are edited there. Changes worth sharing are reconciled back here by hand.
