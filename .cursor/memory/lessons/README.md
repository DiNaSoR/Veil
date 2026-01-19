# Lessons

Each lesson is a separate file with YAML frontmatter for fast, reliable parsing.

## File naming

`L-XXX-short-title.md` (e.g., `L-001-always-flush-after-render.md`)

## Creating a new lesson

1. Copy `templates/lesson.template.md` to this folder
2. Rename to `L-XXX-short-title.md` (use the next available number)
3. Fill in the YAML frontmatter and content
4. Run `scripts/memory/rebuild-memory-index.ps1` (or commit to trigger auto-rebuild)

## Why individual files?

- **Token efficiency**: AI loads only the specific lesson it needs (~200 tokens vs 20k+)
- **Fast search**: Cursor's @-search works best on filenames
- **Easy maintenance**: Edit/delete individual lessons without touching others