# Update Flow

Triggered by: "add this as an instruction to X mode", "update the X mode to", "add X to the Y mode", "remove X from the Y mode"

1. Resolve the target mode via the same fuzzy matching as the load flow (see [load-fallback.md](load-fallback.md) step 2).
2. Read the current mode file.
3. Apply the change:
   - **Add content** — insert into the appropriate section; create the section (with preamble if applicable) if it doesn't exist yet.
   - **Edit content** — locate and revise the relevant line or block.
   - **Remove content** — delete the line or block; if the section is now empty, remove the section heading too.
4. Write the updated file.
5. If the change affects the mode's description, update the `Modes.md` inventory table and `nav.contents` entry.
6. Confirm the change with the user.
