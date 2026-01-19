# Memory Index

This is the entry point for the repository memory system.

## Read order (fast + token-safe)

ALWAYS READ:
1) hot-rules.md (tiny do-not-break list, <20 lines)
2) memo.md (current truth + ownership + active context)

READ IF RELEVANT (search first, open only what matches):
3) lessons/index.md (fast lookup - shows all lesson IDs and rules)
4) lessons/L-XXX-*.md (open ONLY the specific lesson you need)
5) digests/ (monthly digest - read before raw journal)
6) journal/ (raw history - only for archaeology)

## Memory map

- Hot rules: hot-rules.md
- Current truth + Active context: memo.md
- Lessons (individual files): lessons/L-XXX-title.md
- Lessons index (generated): lessons/index.md + lessons-index.json
- Journal (monthly): journal/YYYY-MM.md
- Journal index (generated): journal-index.md + journal-index.json
- Monthly digests (generated): digests/YYYY-MM.digest.md
- Regression checklist: egression-checklist.md
- Tag vocabulary: 	ag-vocabulary.md
- ADRs: dr/

## How to add new memory

- Non-obvious bug or regression -> create a new lesson file in lessons/
- Any meaningful feature/fix -> add a journal entry (monthly file)
- Any stable truth change -> update memo.md and bump the date
- Session context -> update the Active Context section in memo.md
- Any big design/refactor decision -> add an ADR

## Indexing workflow

Indexes are rebuilt automatically via Git pre-commit hook.
Manual rebuild: scripts/memory/rebuild-memory-index.ps1

This regenerates:
- lessons/index.md + lessons-index.json
- journal-index.md + journal-index.json
- digests/YYYY-MM.digest.md
- memory.sqlite (if Python exists)