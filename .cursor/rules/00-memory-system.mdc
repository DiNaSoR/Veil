---
description: Memory System v2 - authority, read order, token-safe retrieval
globs:
alwaysApply: true
---

# Memory System (MANDATORY)

Authority order:
1) .cursor/memory/lessons.md
2) .cursor/memory/memo.md
3) .cursor/memory/journal/ (history)
4) Existing codebase
5) New code

Token-safe workflow:
- ALWAYS read:
  - .cursor/memory/hot-rules.md
  - .cursor/memory/memo.md
- Do NOT read raw journal by default.
  - Read .cursor/memory/digests/<month>.digest.md first.
  - Use .cursor/memory/journal-index.md and targeted search.
- Do NOT read all lessons by default.
  - Read .cursor/memory/lessons-index.md and open only relevant lessons.

After any feature/fix:
- Update the monthly journal in .cursor/memory/journal/YYYY-MM.md.
- If a non-obvious pitfall was discovered, append a new lesson to lessons.md.
- Update memo.md if the "current truth" changed.

Indexing:
- Run scripts/memory/rebuild-memory-index.ps1 after memory updates.