<#
setup-cursor-memory.ps1
Creates a scalable Cursor memory system (Memory v2):
- Curated "always read" memory: hot-rules.md + memo.md
- Append-only lessons + auto-generated lessons index
- Monthly journal + auto-generated digest + journal index
- Cursor rule (.mdc) to enforce behavior
- Helper scripts to rebuild indexes and query memory
- Optional SQLite FTS index (Python-based, if Python is available)

USAGE (from repo root):
  powershell -ExecutionPolicy Bypass -File .\setup-cursor-memory.ps1
  powershell -ExecutionPolicy Bypass -File .\setup-cursor-memory.ps1 -ProjectName "MyProject"
  powershell -ExecutionPolicy Bypass -File .\setup-cursor-memory.ps1 -Force

NOTES:
- By default it will NOT overwrite existing files.
- Use -Force to overwrite files created by this script.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = (Get-Location).Path,
  [string]$ProjectName = "",
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Content,
    [switch]$ForceWrite
  )

  $dir = Split-Path -Parent $Path
  if ($dir -and !(Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  if ((Test-Path $Path) -and (-not $ForceWrite)) {
    Write-Host "SKIP (exists): $Path" -ForegroundColor DarkYellow
    return
  }

  # Normalize line endings to CRLF for Windows readability
  $normalized = ($Content -replace "`r?`n", "`r`n")
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)

  Write-Host "WROTE: $Path" -ForegroundColor Green
}

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (!(Test-Path $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Write-Host "DIR: $Path" -ForegroundColor Green
  }
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
  $ProjectName = Split-Path -Leaf $RepoRoot
}

# Paths
$CursorDir   = Join-Path $RepoRoot ".cursor"
$MemoryDir   = Join-Path $CursorDir "memory"
$RulesDir    = Join-Path $CursorDir "rules"
$JournalDir  = Join-Path $MemoryDir "journal"
$DigestsDir  = Join-Path $MemoryDir "digests"
$AdrDir      = Join-Path $MemoryDir "adr"
$LessonsDir  = Join-Path $MemoryDir "lessons"
$TemplatesDir= Join-Path $MemoryDir "templates"
$ScriptsDir  = Join-Path $RepoRoot "scripts"
$MemScripts  = Join-Path $ScriptsDir "memory"
$GitHooksDir = Join-Path $RepoRoot ".git\hooks"

Ensure-Dir $CursorDir
Ensure-Dir $MemoryDir
Ensure-Dir $RulesDir
Ensure-Dir $JournalDir
Ensure-Dir $DigestsDir
Ensure-Dir $AdrDir
Ensure-Dir $LessonsDir
Ensure-Dir $TemplatesDir
Ensure-Dir $ScriptsDir
Ensure-Dir $MemScripts

$month = (Get-Date -Format "yyyy-MM")
$today = (Get-Date -Format "yyyy-MM-dd")

# -------------------------
# Memory files
# -------------------------

$indexMd = @"
# Memory Index

This is the entry point for the repository memory system.

## Read order (fast + token-safe)

ALWAYS READ:
1) `hot-rules.md` (tiny do-not-break list, <20 lines)
2) `memo.md` (current truth + ownership + active context)

READ IF RELEVANT (search first, open only what matches):
3) `lessons/index.md` (fast lookup - shows all lesson IDs and rules)
4) `lessons/L-XXX-*.md` (open ONLY the specific lesson you need)
5) `digests/` (monthly digest - read before raw journal)
6) `journal/` (raw history - only for archaeology)

## Memory map

- Hot rules: `hot-rules.md`
- Current truth + Active context: `memo.md`
- Lessons (individual files): `lessons/L-XXX-title.md`
- Lessons index (generated): `lessons/index.md` + `lessons-index.json`
- Journal (monthly): `journal/YYYY-MM.md`
- Journal index (generated): `journal-index.md` + `journal-index.json`
- Monthly digests (generated): `digests/YYYY-MM.digest.md`
- Regression checklist: `regression-checklist.md`
- Tag vocabulary: `tag-vocabulary.md`
- ADRs: `adr/`

## How to add new memory

- Non-obvious bug or regression -> create a new lesson file in `lessons/`
- Any meaningful feature/fix -> add a journal entry (monthly file)
- Any stable truth change -> update memo.md and bump the date
- Session context -> update the Active Context section in memo.md
- Any big design/refactor decision -> add an ADR

## Indexing workflow

Indexes are rebuilt automatically via Git pre-commit hook.
Manual rebuild: `scripts/memory/rebuild-memory-index.ps1`

This regenerates:
- lessons/index.md + lessons-index.json
- journal-index.md + journal-index.json
- digests/YYYY-MM.digest.md
- memory.sqlite (if Python exists)
"@

$hotRules = @"
# Hot Rules (MUST READ)

Keep this file short. If it grows, move content into memo/lessons.

1) Do NOT break lessons. Lessons override everything.
2) Memo is current truth (ownership + invariants).
3) Do NOT scan raw journals by default. Use indexes/digests first.
4) Reuse existing patterns and owners. Do not create parallel systems.
5) After any feature/fix: update journal. If a new pitfall is discovered: add a lesson.
"@

$memo = @"
# Project Memo - $ProjectName

Last updated: $today

## Active Context (clear after merging)

- Current Goal: <What are you working on right now?>
- Constraint: <Any temporary constraints or compatibility requirements?>
- Files in focus: <Key files being modified>
- Blocker: <What's blocking progress, if anything?>

## Ownership map

- UI / Frontend owner: <path/module>
- Backend / Server owner: <path/module>
- Data parsing / protocol owner: <path/module>
- Build/CI owner: <path/module>

## Current truth (high-signal)

- <Add invariants that are true right now>
- <Add key toggles/defaults that must not drift>
- <Add any critical lifecycle/timing rules>

## Open questions / TODO

- <What is unknown or risky?>

## Session notes

When you say "I'm done" or "Merge this", remember to:
1. Clear the Active Context section above
2. Add a journal entry if the work was significant
3. Create a lesson if you discovered a non-obvious pitfall
"@

$lessonsReadme = @"
# Lessons

Each lesson is a separate file with YAML frontmatter for fast, reliable parsing.

## File naming

``L-XXX-short-title.md`` (e.g., ``L-001-always-flush-after-render.md``)

## Creating a new lesson

1. Copy ``templates/lesson.template.md`` to this folder
2. Rename to ``L-XXX-short-title.md`` (use the next available number)
3. Fill in the YAML frontmatter and content
4. Run ``scripts/memory/rebuild-memory-index.ps1`` (or commit to trigger auto-rebuild)

## Why individual files?

- **Token efficiency**: AI loads only the specific lesson it needs (~200 tokens vs 20k+)
- **Fast search**: Cursor's @-search works best on filenames
- **Easy maintenance**: Edit/delete individual lessons without touching others
"@

$lessonsIndex = @"
# Lessons Index (generated)

Generated by ``scripts/memory/rebuild-memory-index.ps1``.

Format: ID | [Tags] | AppliesTo | Rule

(No lessons yet. Create your first lesson in the lessons/ folder.)
"@

$journalReadme = @"
# Journal

- One file per month: `YYYY-MM.md`
- Each date appears once per file.
- Keep entries high-signal (what changed / why / key files).
- Put long narratives in Docs/WorkLogs and link them from the journal.

Rule of thumb:
- The journal is history.
- The digest is what the AI should read first.
"@

$journalMonth = @"
# Development Journal - $ProjectName ($month)

## $today

- [Process] Initialized memory system (Memory v2)
  - Why: Establish scalable AI memory (curated truth + indexed retrieval + digest layer)
  - Key files:
    - `.cursor/memory/*`
    - `.cursor/rules/00-memory-system.mdc`
    - `scripts/memory/*`
"@

$digestsReadme = @"
# Digests

Digests are generated summaries of journal months.

Purpose:
- Give the AI a small, token-cheap overview of what changed.
- Avoid reading the raw journal unless needed.

Generated by:
- `scripts/memory/rebuild-memory-index.ps1`
"@

$adrReadme = @"
# ADRs (Architecture Decision Records)

Use ADRs for decisions that explain "why we built it this way".

Naming:
- `ADR-001-short-title.md`
- Keep them short: Context -> Decision -> Consequences
"@

$tagVocab = @"
# Tag Vocabulary

Use a small fixed vocabulary so search stays reliable.

Recommended tags:
- [UI] - UI behavior, rendering, interaction
- [Layout] - layout groups, anchors, sizing, rects
- [Input] - mouse/keyboard/controller input rules
- [Data] - parsing, payloads, formats, state sync
- [Server] - server-side logic and lifecycle
- [Init] - initialization / load order / startup
- [Build] - compilation, MSBuild, project files
- [CI] - automation, pipelines
- [Release] - packaging, artifacts, uploads
- [Compat] - IL2CPP, runtime constraints, environment quirks
- [Integration] - optional plugins, reflection bridges, external systems
- [Docs] - documentation and changelog work
- [Architecture] - module boundaries, refactors, ownership
- [DX] - developer experience, tooling, maintainability
- [Reliability] - crash prevention, guardrails, self-healing
"@

$regChecklist = @"
# Regression Checklist

Only run what is relevant to your change.

## Build / Compile
- [ ] Build solution / affected projects
- [ ] No new warnings introduced (or documented)

## Runtime / In-Game / Manual (if applicable)
- [ ] UI renders (core screens)
- [ ] Primary interactions still work (clicks, dropdowns, tabs)
- [ ] No obvious null refs / spam logs

## Data / Sync (if applicable)
- [ ] Parsing still works on known payloads
- [ ] State updates do not regress (stale UI, wrong mapping)

## Docs (if applicable)
- [ ] Updated docs pages
- [ ] Updated changelog
"@

# Write memory files
Write-Utf8NoBom (Join-Path $MemoryDir "index.md") $indexMd -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $MemoryDir "hot-rules.md") $hotRules -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $MemoryDir "memo.md") $memo -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $LessonsDir "README.md") $lessonsReadme -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $LessonsDir "index.md") $lessonsIndex -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $JournalDir "README.md") $journalReadme -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $JournalDir "$month.md") $journalMonth -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $DigestsDir "README.md") $digestsReadme -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $AdrDir "README.md") $adrReadme -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $MemoryDir "tag-vocabulary.md") $tagVocab -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $MemoryDir "regression-checklist.md") $regChecklist -ForceWrite:$Force

# -------------------------
# Templates
# -------------------------
$templateLesson = @"
---
id: L-XXX
title: Short descriptive title
status: Active
tags: [UI, Build, Reliability]
introduced: YYYY-MM-DD
applies_to:
  - path/or/glob/**
rule: One sentence. Imperative. Testable.
---

# L-XXX - Short descriptive title

## Symptom

What the user saw or what broke.

## Root cause

The real reason this happened.

## Wrong approach (DO NOT REPEAT)

- What not to do
- Why it fails

## Correct approach

- What to do instead
- Code example if helpful

## References

- Files: ``path/to/file.cs``
- Journal: ``journal/YYYY-MM.md#YYYY-MM-DD``
- Related: L-YYY (if superseding another lesson)
"@

$templateJournal = @"
# Journal Entry Template

- [Area][Type] Title
  - Why: ...
  - Key files:
    - `path/to/file`
  - Notes:
    - <optional>
  - Verification:
    - Build: PASS/FAIL/NOT RUN
    - Runtime: PASS/FAIL/NOT RUN
  - Related:
    - Lesson: L-XXX
    - ADR: ADR-XXX
"@

$templateAdr = @"
# ADR-XXX - Title

Date: YYYY-MM-DD
Status: Proposed | Accepted | Deprecated

## Context
What problem are we solving?

## Decision
What did we choose, specifically?

## Consequences
What gets better/worse? What do we need to watch out for?
"@

$templateDigest = @"
# Monthly Digest - YYYY-MM

Generated summary of the monthly journal.
Keep this short. Link to the journal for details.
"@

Write-Utf8NoBom (Join-Path $TemplatesDir "lesson.template.md") $templateLesson -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $TemplatesDir "journal-entry.template.md") $templateJournal -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $TemplatesDir "adr.template.md") $templateAdr -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $TemplatesDir "digest.template.md") $templateDigest -ForceWrite:$Force

# -------------------------
# Cursor rule: enforce memory usage
# -------------------------
$memoryRule = @"
---
description: Memory System v2 - authority, read order, token-safe retrieval
globs:
alwaysApply: true
---

# Memory System (MANDATORY)

Authority order:
1) `.cursor/memory/lessons.md`
2) `.cursor/memory/memo.md`
3) `.cursor/memory/journal/` (history)
4) Existing codebase
5) New code

Token-safe workflow:
- ALWAYS read:
  - `.cursor/memory/hot-rules.md`
  - `.cursor/memory/memo.md`
- Do NOT read raw journal by default.
  - Read `.cursor/memory/digests/<month>.digest.md` first.
  - Use `.cursor/memory/journal-index.md` and targeted search.
- Do NOT read all lessons by default.
  - Read `.cursor/memory/lessons-index.md` and open only relevant lessons.

After any feature/fix:
- Update the monthly journal in `.cursor/memory/journal/YYYY-MM.md`.
- If a non-obvious pitfall was discovered, append a new lesson to `lessons.md`.
- Update `memo.md` if the "current truth" changed.

Indexing:
- Run `scripts/memory/rebuild-memory-index.ps1` after memory updates.
"@

Write-Utf8NoBom (Join-Path $RulesDir "00-memory-system.mdc") $memoryRule -ForceWrite:$Force

# -------------------------
# Helper scripts
# -------------------------
$rebuildIndex = @'
<#
rebuild-memory-index.ps1
Generates:
- .cursor/memory/lessons/index.md + lessons-index.json
- .cursor/memory/journal-index.md + journal-index.json
- .cursor/memory/digests/YYYY-MM.digest.md
Optionally:
- .cursor/memory/memory.sqlite (SQLite FTS index) if Python exists
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = ""
)

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  if ($PSScriptRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
  } else {
    $RepoRoot = (Get-Location).Path
  }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$FilePath, [string]$Content) {
  $dir = Split-Path -Parent $FilePath
  if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $normalized = ($Content -replace "`r?`n", "`r`n")
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($FilePath, $normalized, $utf8NoBom)
}

# Parse YAML frontmatter from a file
function Parse-YamlFrontmatter([string]$FilePath) {
  $content = Get-Content -Raw -Encoding UTF8 $FilePath
  $result = @{}
  
  # Match YAML frontmatter between --- markers
  if ($content -match '(?ms)^---\r?\n(.*?)\r?\n---') {
    $yaml = $Matches[1]
    
    # Parse simple key: value pairs
    foreach ($line in ($yaml -split "`r?`n")) {
      if ($line -match '^\s*(\w+):\s*(.*)$') {
        $key = $Matches[1].Trim()
        $value = $Matches[2].Trim()
        
        # Handle arrays [item1, item2]
        if ($value -match '^\[(.*)\]$') {
          $items = $Matches[1] -split ',' | ForEach-Object { $_.Trim() }
          $result[$key] = @($items)
        }
        # Handle multi-line arrays (next lines start with -)
        elseif ([string]::IsNullOrWhiteSpace($value)) {
          $result[$key] = @()
        }
        else {
          $result[$key] = $value
        }
      }
      # Handle array items under a key
      elseif ($line -match '^\s+-\s+(.+)$') {
        $lastKey = ($result.Keys | Select-Object -Last 1)
        if ($lastKey -and $result[$lastKey] -is [array]) {
          $result[$lastKey] += $Matches[1].Trim()
        }
      }
    }
  }
  return $result
}

$MemoryDir  = Join-Path $RepoRoot ".cursor\memory"
$LessonsDir = Join-Path $MemoryDir "lessons"
$JournalDir = Join-Path $MemoryDir "journal"
$DigestsDir = Join-Path $MemoryDir "digests"

if (!(Test-Path $LessonsDir)) { New-Item -ItemType Directory -Force -Path $LessonsDir | Out-Null }
if (!(Test-Path $JournalDir)) { throw "Missing: $JournalDir" }

# Parse lessons from individual files with YAML frontmatter
$lessonFiles = Get-ChildItem -Path $LessonsDir -File -Filter "L-*.md" -ErrorAction SilentlyContinue | Sort-Object Name

$lessons = @()
foreach ($lf in $lessonFiles) {
  $yaml = Parse-YamlFrontmatter $lf.FullName
  
  if ($yaml.id) {
    $num = 0
    if ($yaml.id -match 'L-(\d+)') { $num = [int]$Matches[1] }
    
    $lessons += [pscustomobject]@{
      Id = $yaml.id
      Num = $num
      Title = if ($yaml.title) { $yaml.title } else { $lf.BaseName }
      Status = if ($yaml.status) { $yaml.status } else { "Active" }
      Introduced = if ($yaml.introduced) { $yaml.introduced } else { "" }
      Tags = if ($yaml.tags) { @($yaml.tags) } else { @() }
      AppliesTo = if ($yaml.applies_to) { @($yaml.applies_to) } else { @() }
      Rule = if ($yaml.rule) { $yaml.rule } else { $yaml.title }
      File = $lf.Name
    }
  }
}

$lessons = $lessons | Sort-Object Num

# Write lessons index
$gen = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
$lines = @()
$lines += "# Lessons Index (generated)"
$lines += ""
$lines += "Generated: $gen"
$lines += ""
$lines += "Format: ID | [Tags] | AppliesTo | Rule | File"
$lines += ""
foreach ($l in $lessons) {
  $tagText = ($l.Tags | ForEach-Object { "[$_]" }) -join ""
  $appliesText = "(any)"
  if ($l.AppliesTo -and @($l.AppliesTo).Count -gt 0) { $appliesText = ($l.AppliesTo -join ", ") }
  $lines += "$($l.Id) | $tagText | $appliesText | $($l.Rule) | ``$($l.File)``"
}

if (-not $lessons -or @($lessons).Count -eq 0) {
  $lines += "(No lessons yet. Create your first lesson: lessons/L-001-title.md)"
}

Write-Utf8NoBom (Join-Path $LessonsDir "index.md") ($lines -join "`n")
$lessonsJson = if (-not $lessons -or @($lessons).Count -eq 0) { "[]" } else { ConvertTo-Json -InputObject @($lessons) -Depth 6 }
Write-Utf8NoBom (Join-Path $MemoryDir "lessons-index.json") $lessonsJson

# Parse journal months
$journalFiles = Get-ChildItem -Path $JournalDir -File | Where-Object {
  $_.Name -match '^\d{4}-\d{2}\.md$' -and $_.Name -ne 'README.md'
} | Sort-Object Name

$journalEntries = New-Object System.Collections.Generic.List[object]

foreach ($jf in $journalFiles) {
  $text = Get-Content -Raw -Encoding UTF8 $jf.FullName

  $datePattern = '(?m)^##\s+(\d{4}-\d{2}-\d{2}).*$'
  $dateMatches = [regex]::Matches($text, $datePattern)

  for ($i=0; $i -lt $dateMatches.Count; $i++) {
    $date = $dateMatches[$i].Groups[1].Value
    $start = $dateMatches[$i].Index
    $end = if ($i -lt $dateMatches.Count - 1) { $dateMatches[$i+1].Index } else { $text.Length }
    $block = $text.Substring($start, $end - $start)

    # Top-level entries start with "- ["
    $entryPattern = '(?m)^-\s+(\[[^\]]+\]){1,}.*$'
    $entryMatches = [regex]::Matches($block, $entryPattern)

    for ($j=0; $j -lt $entryMatches.Count; $j++) {
      $eStart = $entryMatches[$j].Index
      $eEnd = if ($j -lt $entryMatches.Count - 1) { $entryMatches[$j+1].Index } else { $block.Length }
      $eBlock = $block.Substring($eStart, $eEnd - $eStart).Trim()

      $firstLine = ($eBlock -split "`r?`n")[0].Trim()

      $tags = @()
      foreach ($tm in [regex]::Matches($firstLine, '\[([^\]]+)\]')) { $tags += $tm.Groups[1].Value.Trim() }

      $title = ($firstLine -replace '^-\s+(\[[^\]]+\])+\s*', '').Trim()

      # Extract file-like backtick refs in this entry block
      $files = @()
      foreach ($fm in [regex]::Matches($eBlock, '`([^`]+)`')) {
        $v = $fm.Groups[1].Value.Trim()
        if ($v -match '[/\\]' -or $v -match '\.cs$|\.mdx$|\.md$|\.yml$|\.csproj$|\.ps1$|\.ts$|\.tsx$|\.json$') {
          $files += $v
        }
      }
      $files = $files | Select-Object -Unique

      $journalEntries.Add([pscustomobject]@{
        MonthFile = $jf.Name
        Date = $date
        Tags = $tags
        Title = $title
        Files = $files
      })
    }
  }
}

# Write journal index
$ji = @()
$ji += "# Journal Index (generated)"
$ji += ""
$ji += "Generated: $gen"
$ji += ""
$ji += "Format: YYYY-MM-DD | [Tags] | Title | Files"
$ji += ""

foreach ($e in ($journalEntries | Sort-Object Date, Title)) {
  $tagText = ($e.Tags | ForEach-Object { "[$_]" }) -join ""
  $fileText = "-"
  if ($e.Files -and @($e.Files).Count -gt 0) { $fileText = ($e.Files -join ", ") }
  $ji += "$($e.Date) | $tagText | $($e.Title) | $fileText"
}

Write-Utf8NoBom (Join-Path $MemoryDir "journal-index.md") ($ji -join "`n")
$journalJson = if (-not $journalEntries -or $journalEntries.Count -eq 0) { "[]" } else { ConvertTo-Json -InputObject @($journalEntries.ToArray()) -Depth 6 }
Write-Utf8NoBom (Join-Path $MemoryDir "journal-index.json") $journalJson

# Generate digests per month
foreach ($jf in $journalFiles) {
  $monthName = [System.IO.Path]::GetFileNameWithoutExtension($jf.Name)
  $digestPath = Join-Path $DigestsDir "$monthName.digest.md"
  $text = Get-Content -Raw -Encoding UTF8 $jf.FullName

  $digest = @()
  $digest += "# Monthly Digest - $monthName (generated)"
  $digest += ""
  $digest += "Generated: $gen"
  $digest += ""
  $digest += "This is a token-cheap summary. See ``.cursor/memory/journal/$($jf.Name)`` for details."
  $digest += ""

  $dates = [regex]::Matches($text, '(?m)^##\s+(\d{4}-\d{2}-\d{2}).*$') | ForEach-Object { $_.Groups[1].Value }
  $uniqueDates = $dates | Select-Object -Unique

  foreach ($d in $uniqueDates) {
    $digest += "## $d"
    $digest += ""
    $entriesForDay = $journalEntries | Where-Object { $_.MonthFile -eq $jf.Name -and $_.Date -eq $d }
    foreach ($e in $entriesForDay) {
      $tagText = ($e.Tags | ForEach-Object { "[$_]" }) -join ""
      $digest += "- $tagText $($e.Title)"
    }
    $digest += ""
  }

  Write-Utf8NoBom $digestPath ($digest -join "`n")
}

# Optional: build SQLite index if Python exists
$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -ne $python) {
  $pyScript = Join-Path $RepoRoot "scripts\memory\build-memory-sqlite.py"
  if (Test-Path $pyScript) {
    Write-Host "Python detected; building SQLite index..." -ForegroundColor Cyan
    & $python.Source $pyScript --repo $RepoRoot | Out-Host
  }
} else {
  Write-Host "Python not found; skipping SQLite index build." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "Done. Generated indexes + digests." -ForegroundColor Green
'@

$queryScript = @'
<#
query-memory.ps1
Quick search across the memory system without opening huge files.
Prefer searching indexes/digests first, then open the raw source only if needed.

USAGE:
  powershell -File .\scripts\memory\query-memory.ps1 -Query "LayoutService"
  powershell -File .\scripts\memory\query-memory.ps1 -Query "IL2CPP" -Area Lessons
  powershell -File .\scripts\memory\query-memory.ps1 -Query "2026-01-17" -Area Journal
  powershell -File .\scripts\memory\query-memory.ps1 -Query "auth" -Format AI
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Query,
  [ValidateSet("All","HotRules","Memo","Lessons","Journal","Digests")][string]$Area = "All",
  [ValidateSet("Human","AI")][string]$Format = "Human"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSScriptRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
  $RepoRoot = (Get-Location).Path
}
$MemoryDir = Join-Path $RepoRoot ".cursor\memory"
$LessonsDir = Join-Path $MemoryDir "lessons"

$targets = @()
switch ($Area) {
  "HotRules" { $targets += (Join-Path $MemoryDir "hot-rules.md") }
  "Memo"     { $targets += (Join-Path $MemoryDir "memo.md") }
  "Lessons"  { 
    $targets += (Join-Path $LessonsDir "index.md")
    # Also search individual lesson files
    $lessonFiles = Get-ChildItem -Path $LessonsDir -Filter "L-*.md" -ErrorAction SilentlyContinue
    foreach ($lf in $lessonFiles) { $targets += $lf.FullName }
  }
  "Journal"  { $targets += (Join-Path $MemoryDir "journal-index.md") }
  "Digests"  { $targets += (Join-Path $MemoryDir "digests\*.digest.md") }
  "All" {
    $targets += (Join-Path $MemoryDir "hot-rules.md")
    $targets += (Join-Path $MemoryDir "memo.md")
    $targets += (Join-Path $LessonsDir "index.md")
    $targets += (Join-Path $MemoryDir "journal-index.md")
    $targets += (Join-Path $MemoryDir "digests\*.digest.md")
  }
}

$allMatches = @()

foreach ($t in $targets) {
  $results = Select-String -Path $t -Pattern $Query -SimpleMatch -ErrorAction SilentlyContinue
  if ($results) {
    foreach ($r in $results) {
      $allMatches += $r
    }
  }
}

if ($Format -eq "AI") {
  # AI-friendly output: just file paths for easy @-referencing
  if ($allMatches.Count -eq 0) {
    Write-Host "No matches found for: $Query"
  } else {
    Write-Host "Found $($allMatches.Count) matches. Files to read:"
    $uniqueFiles = $allMatches | ForEach-Object { $_.Path } | Sort-Object -Unique
    foreach ($f in $uniqueFiles) {
      # Convert to relative path for easy @-reference
      $relative = $f.Replace($RepoRoot, "").TrimStart("\", "/")
      Write-Host "  @$relative"
    }
  }
} else {
  # Human-friendly output: full context
  Write-Host "Searching: $Query" -ForegroundColor Cyan
  Write-Host "Area: $Area" -ForegroundColor Cyan
  Write-Host ""

  if ($allMatches.Count -eq 0) {
    Write-Host "No matches found." -ForegroundColor Yellow
  } else {
    $grouped = $allMatches | Group-Object Path
    foreach ($g in $grouped) {
      Write-Host "==> $($g.Name)" -ForegroundColor Green
      foreach ($m in $g.Group) {
        Write-Host "  $($m.LineNumber): $($m.Line.Trim())"
      }
      Write-Host ""
    }
  }
}
'@

$buildSqlitePy = @'
#!/usr/bin/env python3
import argparse
import json
import sqlite3
from pathlib import Path

def read_text(p: Path) -> str:
    # tolerate BOM
    return p.read_text(encoding="utf-8-sig", errors="replace")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    args = ap.parse_args()

    repo = Path(args.repo)
    mem = repo / ".cursor" / "memory"
    lessons_dir = mem / "lessons"
    out_db = mem / "memory.sqlite"

    lessons_index = mem / "lessons-index.json"
    journal_index = mem / "journal-index.json"

    if not journal_index.exists():
        print("Missing journal-index.json. Run rebuild-memory-index.ps1 first.")
        return 2

    # Load lessons from JSON index
    lessons = []
    if lessons_index.exists():
        lessons_text = read_text(lessons_index).strip()
        if lessons_text:
            lessons = json.loads(lessons_text)
            if not isinstance(lessons, list):
                lessons = [lessons] if lessons else []

    # Load journal from JSON index
    journal_text = read_text(journal_index).strip()
    journal = json.loads(journal_text) if journal_text else []
    if not isinstance(journal, list):
        journal = [journal] if journal else []

    if out_db.exists():
        out_db.unlink()

    con = sqlite3.connect(str(out_db))
    cur = con.cursor()

    # FTS for fast local search over memory
    cur.execute("CREATE VIRTUAL TABLE memory_fts USING fts5(kind, id, date, tags, title, content, path);")

    # Insert memo + hot rules as single docs
    hot = mem / "hot-rules.md"
    memo = mem / "memo.md"
    if hot.exists():
        cur.execute("INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                    ("hot_rules","HOT",None,"","Hot Rules",read_text(hot),str(hot)))
    if memo.exists():
        cur.execute("INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                    ("memo","MEMO",None,"","Memo",read_text(memo),str(memo)))

    # Lessons (now from individual files)
    for l in lessons:
        tags = " ".join(l.get("Tags") or [])
        applies = ", ".join(l.get("AppliesTo") or [])
        lesson_file = l.get("File", "")
        lesson_path = lessons_dir / lesson_file if lesson_file else mem / "lessons.md"
        
        # Read full lesson content if file exists
        content = f"{l.get('Title','')}\nRule: {l.get('Rule','')}\nAppliesTo: {applies}"
        if lesson_path.exists():
            content = read_text(lesson_path)
        
        cur.execute("INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                    ("lesson", l.get("Id"), l.get("Introduced"), tags, l.get("Title"), content, str(lesson_path)))

    # Journal entries
    for e in journal:
        tags = " ".join(e.get("Tags") or [])
        files_list = e.get("Files")
        if isinstance(files_list, dict):
            files_list = []  # Handle empty object {}
        files = ", ".join(files_list or [])
        content = f"{e.get('Title','')}\nFiles: {files}"
        cur.execute("INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                    ("journal", None, e.get("Date"), tags, e.get("Title"), content, str(mem / "journal" / e.get("MonthFile",""))))

    con.commit()
    con.close()

    print(f"Built: {out_db}")

if __name__ == "__main__":
    raise SystemExit(main())
'@

Write-Utf8NoBom (Join-Path $MemScripts "rebuild-memory-index.ps1") $rebuildIndex -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $MemScripts "query-memory.ps1") $queryScript -ForceWrite:$Force
Write-Utf8NoBom (Join-Path $MemScripts "build-memory-sqlite.py") $buildSqlitePy -ForceWrite:$Force

# -------------------------
# Git pre-commit hook (auto-rebuild indexes)
# -------------------------
$gitHook = @'
#!/bin/sh
# Auto-rebuild Cursor Memory indexes before commit
# This ensures indexes are always fresh

echo "Rebuilding Cursor Memory indexes..."

# Run the rebuild script
if command -v powershell.exe &> /dev/null; then
    powershell.exe -ExecutionPolicy Bypass -File "./scripts/memory/rebuild-memory-index.ps1" 2>/dev/null
elif command -v pwsh &> /dev/null; then
    pwsh -ExecutionPolicy Bypass -File "./scripts/memory/rebuild-memory-index.ps1" 2>/dev/null
fi

# Stage the updated index files
git add .cursor/memory/lessons/index.md 2>/dev/null
git add .cursor/memory/lessons-index.json 2>/dev/null
git add .cursor/memory/journal-index.md 2>/dev/null
git add .cursor/memory/journal-index.json 2>/dev/null
git add .cursor/memory/digests/*.digest.md 2>/dev/null

exit 0
'@

# Only create git hook if .git/hooks exists
if (Test-Path $GitHooksDir) {
  $hookPath = Join-Path $GitHooksDir "pre-commit"
  
  # Check if hook already exists and contains our marker
  $existingHook = ""
  if (Test-Path $hookPath) {
    $existingHook = Get-Content -Raw -Path $hookPath -ErrorAction SilentlyContinue
  }
  
  if ($existingHook -notmatch "Cursor Memory indexes") {
    if ([string]::IsNullOrWhiteSpace($existingHook)) {
      # No existing hook, create new one
      Write-Utf8NoBom $hookPath $gitHook -ForceWrite:$Force
    } else {
      # Append to existing hook
      $combined = $existingHook.TrimEnd() + "`n`n" + $gitHook
      Write-Utf8NoBom $hookPath $combined -ForceWrite:$true
    }
    Write-Host "HOOK: $hookPath" -ForegroundColor Green
  } else {
    Write-Host "SKIP (exists): Git hook already contains memory rebuild" -ForegroundColor DarkYellow
  }
} else {
  Write-Host "SKIP: .git/hooks not found (not a git repo or hooks disabled)" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1) Create your first lesson: copy templates/lesson.template.md to lessons/L-001-title.md" -ForegroundColor White
Write-Host "  2) Update memo.md with your project's ownership map and current truth" -ForegroundColor White
Write-Host "  3) Indexes auto-rebuild on git commit (or run manually):" -ForegroundColor White
Write-Host "     powershell -ExecutionPolicy Bypass -File .\scripts\memory\rebuild-memory-index.ps1" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Search examples:" -ForegroundColor Cyan
Write-Host "  powershell -File .\scripts\memory\query-memory.ps1 -Query ""auth"" -Area All" -ForegroundColor DarkGray
Write-Host "  powershell -File .\scripts\memory\query-memory.ps1 -Query ""render"" -Format AI" -ForegroundColor DarkGray
Write-Host ""
