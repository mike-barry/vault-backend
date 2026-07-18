# Reading Capture Flow

Fetch a URL and save it as a reading note in `Areas/Research/Inbox/`. Triggered whenever the user shares a URL and says "save this", "save this for later", "add this to my reading list", "save this article", or anything implying they want to bookmark content to read later. Don't wait for the user to be explicit — if they share a URL with intent to save it, use this flow.

## Steps

### 1. Fetch the URL

Fetch the page content from the URL the user provided. Extract:
- The article title (for the display title and filename)
- A one-paragraph summary of what the article covers and why it's worth keeping
- 3–5 concrete key takeaways — specific points worth remembering, not generic observations

### 2. Write the Note

**Filename**: `Reading-Title.md` — the `Reading` type prefix, then a short title derived from the article title in `Title-Case-With-Hyphens` (e.g. `Reading-An-Interesting-Article.md`). No special characters.

**Destination**: `Areas/Research/Inbox/`

**Template** (`doc.created` + `doc.type: Reading` — schema per [[Document-Conventions]]):

```markdown
---
doc.created: YYYY-MM-DD
doc.type: Reading
---

# Article Title

**Link:** [Article Title](https://...)
**Added:** YYYY-MM-DD

## Summary

One paragraph describing what the article covers and why it's worth keeping.

## Key Takeaways

- Concrete point worth remembering
- Concrete point worth remembering
- Concrete point worth remembering
```

After writing the file, inject the skill-owned-file directive by running `scripts/add-skill-directive.ps1 -DocPath <path> -When 'editing this file'`.

### 3. Offer a Read-Later Task

Ask the user: "Want me to add a task to read this?"

- If **yes**: invoke the `vault-tasks` skill to add a task to the Research area. Task text: `Read [[Article-Slug]]` (use the actual filename slug, no `.md`).
- If **no**: you are done.
