<#
setup-cursor-memory.ps1
Creates a scalable Cursor memory system (Memory v3):
- Curated "always read" memory: hot-rules.md + active-context.md + memo.md
- Atomic lessons (individual files) + auto-generated lessons index
- Monthly journal + auto-generated digest + journal index
- Cursor rule (.mdc) to enforce behavior
- Helper scripts: rebuild indexes, query, lint, add-lesson, add-journal-entry
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

Keep this file <20 lines. Move content to memo/lessons if it grows.

## Authority Order (highest to lowest)
1) Lessons override EVERYTHING (including active-context)
2) active-context.md overrides memo/journal (but NOT lessons)
3) memo.md is long-term project truth
4) journal is history

## Retrieval Rules
5) Do NOT scan raw journals. Use indexes/digests first.
6) Reuse existing patterns. Check memo.md ownership before creating new systems.
7) When done: clear active-context.md, add journal entry if significant.
"@

$activeContext = @"
# Active Context (Session Scratchpad)

This file captures the **current session state**. It takes priority over older journal entries.

**CLEAR THIS FILE** when your task is done (run ``scripts/memory/clear-active.ps1``).

## Current Goal

- 

## Files in Focus

- 

## Recent Attempts / Findings

- 

## Temporary Constraints

- 

## Blockers

- 
"@

$memo = @"
# Project Memo - $ProjectName

Last updated: $today

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

- [Process] Initialized memory system (Memory v3)
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
Write-Utf8NoBom (Join-Path $MemoryDir "active-context.md") $activeContext -ForceWrite:$Force
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
triggers:
  - error message keyword
  - crash signature
  - related symptom
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
description: Memory System v3 - Authority, Atomic Retrieval, Active Context
globs:
alwaysApply: true
---

# Memory System (MANDATORY)

## Authority Order (highest to lowest)
1) Lessons override EVERYTHING (including active-context)
2) ``active-context.md`` overrides memo/journal (but NOT lessons)
3) ``memo.md`` is long-term project truth
4) Journal is history
5) Existing codebase
6) New suggestions (lowest priority)

## Token-Safe Retrieval

ALWAYS READ (in order):
1. ``.cursor/memory/hot-rules.md`` (tiny, <20 lines)
2. ``.cursor/memory/active-context.md`` (current session state)
3. ``.cursor/memory/memo.md`` (project truth + ownership)

SEARCH FIRST, THEN FETCH:
4. ``.cursor/memory/lessons/index.md`` -> find relevant lesson ID
5. ``.cursor/memory/lessons/L-XXX-title.md`` -> load ONLY the specific file
6. ``.cursor/memory/digests/YYYY-MM.digest.md`` -> before raw journal
7. ``.cursor/memory/journal/YYYY-MM.md`` -> only for archaeology

## After Any Feature/Fix

1. Update ``active-context.md`` during work (scratchpad)
2. Add journal entry to ``journal/YYYY-MM.md`` when done
3. Create ``lessons/L-XXX-title.md`` if you discovered a pitfall
4. Update ``memo.md`` if project truth changed
5. Clear ``active-context.md`` when task is merged

## Automation

- Indexes auto-rebuild via Git pre-commit hook
- Manual: ``scripts/memory/rebuild-memory-index.ps1``
- Clear session: ``scripts/memory/clear-active.ps1``
- Lint: ``scripts/memory/lint-memory.ps1``
- Add lesson: ``scripts/memory/add-lesson.ps1``
- Add journal: ``scripts/memory/add-journal-entry.ps1``

## AI Behavior

- When user says "I'm done" or "merge this" -> remind to clear active-context
- When you discover a bug pattern -> suggest creating a lesson
- When unsure about architecture -> check lessons/index.md first
- Don't create parallel systems -> check memo.md ownership map
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

# Parse YAML frontmatter from a file (deterministic, tracks current list key explicitly)
function Parse-YamlFrontmatter([string]$FilePath) {
  $content = Get-Content -Raw -Encoding UTF8 $FilePath
  $result = @{}
  $currentListKey = $null  # Track which key is currently receiving list items
  
  # Match YAML frontmatter between --- markers
  if ($content -match '(?ms)^---\r?\n(.*?)\r?\n---') {
    $yaml = $Matches[1]
    
    foreach ($line in ($yaml -split "`r?`n")) {
      # Skip empty lines and comments
      if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*#') {
        continue
      }
      
      # Check for key: value pattern
      if ($line -match '^([a-zA-Z_][a-zA-Z0-9_]*):\s*(.*)$') {
        $key = $Matches[1].Trim().ToLower()
        $value = $Matches[2].Trim()
        
        # Handle inline arrays [item1, item2]
        if ($value -match '^\[(.*)\]$') {
          $items = @()
          $innerContent = $Matches[1]
          if (-not [string]::IsNullOrWhiteSpace($innerContent)) {
            $items = $innerContent -split ',' | ForEach-Object { $_.Trim() }
          }
          $result[$key] = $items
          $currentListKey = $null  # Inline array is complete
        }
        # Empty value - might be start of multi-line array
        elseif ([string]::IsNullOrWhiteSpace($value)) {
          $result[$key] = @()
          $currentListKey = $key  # This key will receive list items
        }
        # Simple scalar value
        else {
          $result[$key] = $value
          $currentListKey = $null
        }
      }
      # Check for list item (- value)
      elseif ($line -match '^\s+-\s+(.+)$') {
        $itemValue = $Matches[1].Trim()
        if ($currentListKey -and $result.ContainsKey($currentListKey)) {
          $result[$currentListKey] += $itemValue
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

# Token usage monitoring for "always read" layer
$hotFiles = @(
  (Join-Path $MemoryDir "hot-rules.md"),
  (Join-Path $MemoryDir "active-context.md"),
  (Join-Path $MemoryDir "memo.md")
)
$totalChars = 0
foreach ($hf in $hotFiles) {
  if (Test-Path $hf) {
    $totalChars += (Get-Content $hf -Raw -ErrorAction SilentlyContinue).Length
  }
}

# Rough estimate: 4 chars ≈ 1 token
$estimatedTokens = [math]::Round($totalChars / 4)

Write-Host ""
if ($totalChars -gt 8000) {
  Write-Host "WARNING: Always-read layer is $totalChars chars (~$estimatedTokens tokens)" -ForegroundColor Yellow
  Write-Host "  Consider moving content from memo.md to lessons, or clearing active-context.md" -ForegroundColor Yellow
} else {
  Write-Host "Always-read layer: $totalChars chars (~$estimatedTokens tokens) - Healthy" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Generated indexes + digests." -ForegroundColor Green
'@

$queryScript = @'
<#
query-memory.ps1
Quick search across the memory system.
Uses SQLite FTS if available, falls back to Select-String.

USAGE:
  powershell -File .\scripts\memory\query-memory.ps1 -Query "LayoutService"
  powershell -File .\scripts\memory\query-memory.ps1 -Query "IL2CPP" -Area Lessons
  powershell -File .\scripts\memory\query-memory.ps1 -Query "auth" -Format AI
  powershell -File .\scripts\memory\query-memory.ps1 -Query "render" -UseSqlite
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Query,
  [ValidateSet("All","HotRules","Memo","Lessons","Journal","Digests")][string]$Area = "All",
  [ValidateSet("Human","AI")][string]$Format = "Human",
  [switch]$UseSqlite
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
$SqliteDb = Join-Path $MemoryDir "memory.sqlite"

# Check if we should use SQLite
$useSqliteSearch = $false
if ($UseSqlite -or (Test-Path $SqliteDb)) {
  # Check if Python is available for SQLite queries
  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) {
    $useSqliteSearch = $true
  }
}

if ($useSqliteSearch) {
  # Use SQLite FTS for search
  Write-Host "Using SQLite FTS search..." -ForegroundColor Cyan
  
  $pythonScript = @"
import sqlite3
import sys

db_path = sys.argv[1]
query = sys.argv[2]
area = sys.argv[3]
format_type = sys.argv[4]

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Build WHERE clause based on area
area_filter = ""
if area == "HotRules":
    area_filter = "AND kind = 'hot_rules'"
elif area == "Memo":
    area_filter = "AND kind = 'memo'"
elif area == "Lessons":
    area_filter = "AND kind = 'lesson'"
elif area == "Journal":
    area_filter = "AND kind = 'journal'"

# FTS5 search
sql = f'''
SELECT kind, id, title, path, 
       snippet(memory_fts, 5, '>>>', '<<<', '...', 32) as snippet
FROM memory_fts 
WHERE memory_fts MATCH ? {area_filter}
ORDER BY rank
LIMIT 20
'''

try:
    cursor.execute(sql, (query,))
    results = cursor.fetchall()
    
    if format_type == "AI":
        if results:
            print(f"Found {len(results)} matches. Files to read:")
            seen_paths = set()
            for row in results:
                path = row[3]
                if path not in seen_paths:
                    seen_paths.add(path)
                    # Make path relative - handle Windows paths
                    path_normalized = path.replace('\\', '/')
                    if '.cursor/' in path_normalized:
                        rel_path = '.cursor/' + path_normalized.split('.cursor/')[-1]
                        print(f"  @{rel_path}")
                    else:
                        print(f"  @{path}")
        else:
            print(f"No matches found for: {query}")
    else:
        if results:
            print(f"Found {len(results)} matches for '{query}':")
            print()
            for row in results:
                kind, id_val, title, path, snippet = row
                print(f"[{kind}] {title or id_val}")
                print(f"  Path: {path}")
                if snippet:
                    print(f"  Match: {snippet}")
                print()
        else:
            print(f"No matches found for: {query}")
            
except sqlite3.OperationalError as e:
    # FTS syntax error - try simple LIKE search
    sql = f'''
    SELECT kind, id, title, path, content
    FROM memory_fts 
    WHERE content LIKE ? {area_filter}
    LIMIT 20
    '''
    cursor.execute(sql, (f'%{query}%',))
    results = cursor.fetchall()
    
    if format_type == "AI":
        if results:
            print(f"Found {len(results)} matches. Files to read:")
            seen_paths = set()
            for row in results:
                path = row[3]
                if path not in seen_paths:
                    seen_paths.add(path)
                    print(f"  @{path}")
        else:
            print(f"No matches found for: {query}")
    else:
        if results:
            for row in results:
                kind, id_val, title, path, content = row
                print(f"[{kind}] {title or id_val}: {path}")
        else:
            print(f"No matches found for: {query}")

conn.close()
"@

  # Run Python script
  $pythonScript | & $python.Source - $SqliteDb $Query $Area $Format
  
} else {
  # Fallback to Select-String search
  Write-Host "Using file-based search (SQLite not available)..." -ForegroundColor DarkYellow
  
  $targets = @()
  switch ($Area) {
    "HotRules" { $targets += (Join-Path $MemoryDir "hot-rules.md") }
    "Memo"     { $targets += (Join-Path $MemoryDir "memo.md") }
    "Lessons"  { 
      $targets += (Join-Path $LessonsDir "index.md")
      $lessonFiles = Get-ChildItem -Path $LessonsDir -Filter "L-*.md" -ErrorAction SilentlyContinue
      foreach ($lf in $lessonFiles) { $targets += $lf.FullName }
    }
    "Journal"  { $targets += (Join-Path $MemoryDir "journal-index.md") }
    "Digests"  { $targets += (Join-Path $MemoryDir "digests\*.digest.md") }
    "All" {
      $targets += (Join-Path $MemoryDir "hot-rules.md")
      $targets += (Join-Path $MemoryDir "active-context.md")
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
    $matchCount = if ($allMatches) { @($allMatches).Count } else { 0 }
    if ($matchCount -eq 0) {
      Write-Host "No matches found for: $Query"
    } else {
      Write-Host "Found $matchCount matches. Files to read:"
      $uniqueFiles = $allMatches | ForEach-Object { $_.Path } | Sort-Object -Unique
      foreach ($f in $uniqueFiles) {
        $relative = $f.Replace($RepoRoot, "").TrimStart("\", "/")
        Write-Host "  @$relative"
      }
    }
  } else {
    Write-Host "Searching: $Query" -ForegroundColor Cyan
    Write-Host "Area: $Area" -ForegroundColor Cyan
    Write-Host ""

    $matchCount = if ($allMatches) { @($allMatches).Count } else { 0 }
    if ($matchCount -eq 0) {
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
# Clear active context script
# -------------------------
$clearActive = @'
<#
clear-active.ps1
Resets active-context.md to a blank template.
Run this when your task is complete.
#>

$RepoRoot = if ($PSScriptRoot) { 
  (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path 
} else { 
  (Get-Location).Path 
}

$ActivePath = Join-Path $RepoRoot ".cursor\memory\active-context.md"

$Template = @"
# Active Context (Session Scratchpad)

This file captures the **current session state**. It takes priority over older journal entries.

**CLEAR THIS FILE** when your task is done (run ``scripts/memory/clear-active.ps1``).

## Current Goal

- 

## Files in Focus

- 

## Recent Attempts / Findings

- 

## Temporary Constraints

- 

## Blockers

- 
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ActivePath, ($Template -replace "`r?`n", "`r`n"), $utf8NoBom)

Write-Host "Cleared: $ActivePath" -ForegroundColor Green
Write-Host "Active context reset to blank template." -ForegroundColor Cyan
'@

Write-Utf8NoBom (Join-Path $MemScripts "clear-active.ps1") $clearActive -ForceWrite:$Force

# -------------------------
# Lint memory script
# -------------------------
$lintMemory = @'
<#
lint-memory.ps1
Validates the memory system for common issues:
- Duplicate lesson IDs
- Duplicate journal date headings
- Missing required YAML fields in lessons
- Lessons without proper ID format
- Token budget warnings

USAGE:
  powershell -File .\scripts\memory\lint-memory.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSScriptRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
  $RepoRoot = (Get-Location).Path
}

$MemoryDir = Join-Path $RepoRoot ".cursor\memory"
$LessonsDir = Join-Path $MemoryDir "lessons"
$JournalDir = Join-Path $MemoryDir "journal"

$errors = @()
$warnings = @()

Write-Host "Linting Cursor Memory System..." -ForegroundColor Cyan
Write-Host ""

# -------------------------
# 1. Check lesson files
# -------------------------
Write-Host "Checking lessons..." -ForegroundColor White

$lessonFiles = Get-ChildItem -Path $LessonsDir -Filter "L-*.md" -ErrorAction SilentlyContinue
$lessonIds = @{}
$requiredFields = @("id", "title", "rule")

foreach ($lf in $lessonFiles) {
  $content = Get-Content -Raw -Encoding UTF8 $lf.FullName
  
  # Check for YAML frontmatter
  if (-not ($content -match '(?ms)^---\r?\n(.*?)\r?\n---')) {
    $errors += "[$($lf.Name)] Missing YAML frontmatter"
    continue
  }
  
  $yaml = $Matches[1]
  $meta = @{}
  
  # Parse YAML
  foreach ($line in ($yaml -split "`r?`n")) {
    if ($line -match '^([a-zA-Z_][a-zA-Z0-9_]*):\s*(.*)$') {
      $key = $Matches[1].Trim().ToLower()
      $value = $Matches[2].Trim()
      if ($value -match '^\[(.*)\]$') {
        $meta[$key] = $Matches[1]
      } else {
        $meta[$key] = $value
      }
    }
  }
  
  # Check required fields
  foreach ($field in $requiredFields) {
    if (-not $meta[$field] -or [string]::IsNullOrWhiteSpace($meta[$field])) {
      $errors += "[$($lf.Name)] Missing required field: $field"
    }
  }
  
  # Check ID format
  if ($meta["id"]) {
    $id = $meta["id"]
    if (-not ($id -match '^L-\d{3}$')) {
      $warnings += "[$($lf.Name)] ID '$id' doesn't match format L-XXX (3 digits)"
    }
    
    # Check for duplicates
    if ($lessonIds.ContainsKey($id)) {
      $errors += "[$($lf.Name)] Duplicate ID '$id' (also in $($lessonIds[$id]))"
    } else {
      $lessonIds[$id] = $lf.Name
    }
    
    # Check filename matches ID
    $expectedPrefix = $id.ToLower()
    if (-not $lf.Name.ToLower().StartsWith($expectedPrefix)) {
      $warnings += "[$($lf.Name)] Filename doesn't start with ID '$id'"
    }
  }
  
  # Check status field
  if ($meta["status"]) {
    $validStatuses = @("Active", "Superseded", "Deprecated", "Draft")
    if ($meta["status"] -notin $validStatuses) {
      $warnings += "[$($lf.Name)] Unknown status '$($meta["status"])' (expected: $($validStatuses -join ', '))"
    }
  }
}

$lessonCount = if ($lessonFiles) { @($lessonFiles).Count } else { 0 }
Write-Host "  Found $lessonCount lesson files" -ForegroundColor Gray

# -------------------------
# 2. Check journal files for duplicate dates
# -------------------------
Write-Host "Checking journals..." -ForegroundColor White

$journalFiles = Get-ChildItem -Path $JournalDir -Filter "*.md" -ErrorAction SilentlyContinue | 
  Where-Object { $_.Name -match '^\d{4}-\d{2}\.md$' }

foreach ($jf in $journalFiles) {
  $content = Get-Content -Raw -Encoding UTF8 $jf.FullName
  $dateMatches = [regex]::Matches($content, '(?m)^##\s+(\d{4}-\d{2}-\d{2})')
  
  $dates = @{}
  foreach ($dm in $dateMatches) {
    $date = $dm.Groups[1].Value
    if ($dates.ContainsKey($date)) {
      $dates[$date]++
      $errors += "[$($jf.Name)] Duplicate date heading: $date (appears $($dates[$date]) times)"
    } else {
      $dates[$date] = 1
    }
  }
}

$journalCount = if ($journalFiles) { @($journalFiles).Count } else { 0 }
Write-Host "  Found $journalCount journal files" -ForegroundColor Gray

# -------------------------
# 3. Check token budget
# -------------------------
Write-Host "Checking token budget..." -ForegroundColor White

$hotFiles = @(
  (Join-Path $MemoryDir "hot-rules.md"),
  (Join-Path $MemoryDir "active-context.md"),
  (Join-Path $MemoryDir "memo.md")
)

$totalChars = 0
foreach ($hf in $hotFiles) {
  if (Test-Path $hf) {
    $chars = (Get-Content $hf -Raw -ErrorAction SilentlyContinue).Length
    $totalChars += $chars
    
    # Warn if individual file is too large
    if ($chars -gt 3000) {
      $warnings += "[$(Split-Path $hf -Leaf)] File is $chars chars (~$([math]::Round($chars/4)) tokens) - consider trimming"
    }
  }
}

$estimatedTokens = [math]::Round($totalChars / 4)
Write-Host "  Always-read layer: $totalChars chars (~$estimatedTokens tokens)" -ForegroundColor Gray

if ($totalChars -gt 8000) {
  $errors += "[Token Budget] Always-read layer exceeds 8000 chars (~2000 tokens)"
} elseif ($totalChars -gt 6000) {
  $warnings += "[Token Budget] Always-read layer is $totalChars chars - approaching limit"
}

# -------------------------
# 4. Check for orphaned files
# -------------------------
Write-Host "Checking for orphans..." -ForegroundColor White

# Check if lessons index exists
$lessonsIndex = Join-Path $LessonsDir "index.md"
if (-not (Test-Path $lessonsIndex)) {
  $warnings += "[lessons/index.md] Missing - run rebuild-memory-index.ps1"
}

# Check if journal index exists  
$journalIndex = Join-Path $MemoryDir "journal-index.md"
if (-not (Test-Path $journalIndex)) {
  $warnings += "[journal-index.md] Missing - run rebuild-memory-index.ps1"
}

# -------------------------
# Report results
# -------------------------
Write-Host ""
Write-Host "====== LINT RESULTS ======" -ForegroundColor White

$errorCount = if ($errors) { @($errors).Count } else { 0 }
$warningCount = if ($warnings) { @($warnings).Count } else { 0 }

if ($errorCount -eq 0 -and $warningCount -eq 0) {
  Write-Host "All checks passed!" -ForegroundColor Green
} else {
  if ($errorCount -gt 0) {
    Write-Host ""
    Write-Host "ERRORS ($errorCount):" -ForegroundColor Red
    foreach ($e in $errors) {
      Write-Host "  ERROR: $e" -ForegroundColor Red
    }
  }
  
  if ($warningCount -gt 0) {
    Write-Host ""
    Write-Host "WARNINGS ($warningCount):" -ForegroundColor Yellow
    foreach ($w in $warnings) {
      Write-Host "  WARN: $w" -ForegroundColor Yellow
    }
  }
}

Write-Host ""

# Return exit code
if ($errorCount -gt 0) {
  Write-Host "Lint failed with $errorCount error(s)" -ForegroundColor Red
  exit 1
} else {
  Write-Host "Lint passed" -ForegroundColor Green
  exit 0
}
'@

Write-Utf8NoBom (Join-Path $MemScripts "lint-memory.ps1") $lintMemory -ForceWrite:$Force

# -------------------------
# Add lesson helper script
# -------------------------
$addLesson = @'
<#
add-lesson.ps1
Creates a new lesson file with proper ID and YAML frontmatter.
Automatically assigns the next available lesson ID.

USAGE:
  powershell -File .\scripts\memory\add-lesson.ps1 -Title "Always validate input" -Tags "Security,Validation" -Rule "Validate all user input before processing"
  powershell -File .\scripts\memory\add-lesson.ps1 -Title "Use async await" -Tags "Performance" -AppliesTo "src/**/*.ts"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Title,
  [Parameter(Mandatory=$true)][string]$Tags,
  [Parameter(Mandatory=$true)][string]$Rule,
  [string]$AppliesTo = "*",
  [string]$Triggers = "",
  [string]$Symptom = "TODO: Describe what happened",
  [string]$RootCause = "TODO: Describe why it happened"
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

# Ensure lessons directory exists
if (-not (Test-Path $LessonsDir)) {
  New-Item -ItemType Directory -Force -Path $LessonsDir | Out-Null
}

# Find next available ID
$existingLessons = Get-ChildItem -Path $LessonsDir -Filter "L-*.md" -ErrorAction SilentlyContinue
$maxId = 0

foreach ($lf in $existingLessons) {
  if ($lf.Name -match '^L-(\d{3})') {
    $id = [int]$Matches[1]
    if ($id -gt $maxId) { $maxId = $id }
  }
}

$nextId = $maxId + 1
$lessonId = "L-{0:D3}" -f $nextId

# Create kebab-case filename
$kebabTitle = $Title.ToLower() -replace '[^a-z0-9]+', '-' -replace '^-|-$', ''
$kebabTitle = $kebabTitle.Substring(0, [Math]::Min(50, $kebabTitle.Length))  # Limit length
$fileName = "$lessonId-$kebabTitle.md"
$filePath = Join-Path $LessonsDir $fileName

# Format tags
$tagList = $Tags -split ',' | ForEach-Object { $_.Trim() }
$tagsYaml = "[$($tagList -join ', ')]"

# Format applies_to
$appliesLines = @()
foreach ($a in ($AppliesTo -split ',')) {
  $appliesLines += "  - $($a.Trim())"
}
$appliesYaml = $appliesLines -join "`r`n"

# Format triggers
$triggersYaml = ""
if ($Triggers) {
  $triggerLines = @()
  foreach ($t in ($Triggers -split ',')) {
    $triggerLines += "  - $($t.Trim())"
  }
  $triggersYaml = "triggers:`r`n" + ($triggerLines -join "`r`n")
} else {
  $triggersYaml = "triggers:`r`n  - TODO: add error messages or keywords that indicate this lesson"
}

$today = Get-Date -Format "yyyy-MM-dd"

$content = @"
---
id: $lessonId
title: $Title
status: Active
tags: $tagsYaml
introduced: $today
applies_to:
$appliesYaml
$triggersYaml
rule: $Rule
---

# $lessonId - $Title

## Symptom

$Symptom

## Root Cause

$RootCause

## Wrong Approach (DO NOT REPEAT)

- TODO: What not to do

## Correct Approach

- TODO: What to do instead

## References

- Files: ``TODO``
- Journal: ``journal/$($today.Substring(0,7)).md#$today``
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($filePath, ($content -replace "`r?`n", "`r`n"), $utf8NoBom)

Write-Host "Created lesson: $filePath" -ForegroundColor Green
Write-Host "  ID: $lessonId" -ForegroundColor Gray
Write-Host "  Title: $Title" -ForegroundColor Gray
Write-Host "  Tags: $tagsYaml" -ForegroundColor Gray
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1) Edit the file to fill in TODO sections" -ForegroundColor White
Write-Host "  2) Run: scripts\memory\rebuild-memory-index.ps1" -ForegroundColor White
'@

Write-Utf8NoBom (Join-Path $MemScripts "add-lesson.ps1") $addLesson -ForceWrite:$Force

# -------------------------
# Add journal entry helper script
# -------------------------
$addJournalEntry = @'
<#
add-journal-entry.ps1
Adds a journal entry to the current month's journal file.
Ensures only one heading per date (appends to existing date if present).

USAGE:
  powershell -File .\scripts\memory\add-journal-entry.ps1 -Tags "UI,Fix" -Title "Fixed button alignment"
  powershell -File .\scripts\memory\add-journal-entry.ps1 -Tags "Build" -Title "Updated dependencies" -Files "package.json"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Tags,
  [Parameter(Mandatory=$true)][string]$Title,
  [string]$Files = "",
  [string]$Why = "",
  [string]$Date = (Get-Date -Format "yyyy-MM-dd")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSScriptRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
  $RepoRoot = (Get-Location).Path
}

$MemoryDir = Join-Path $RepoRoot ".cursor\memory"
$JournalDir = Join-Path $MemoryDir "journal"

# Ensure journal directory exists
if (-not (Test-Path $JournalDir)) {
  New-Item -ItemType Directory -Force -Path $JournalDir | Out-Null
}

# Get month from date
$month = $Date.Substring(0, 7)  # YYYY-MM
$journalFile = Join-Path $JournalDir "$month.md"

# Format tags
$tagList = $Tags -split ',' | ForEach-Object { "[$($_.Trim())]" }
$tagString = $tagList -join ""

# Build entry
$entryLines = @()
$entryLines += "- $tagString $Title"
if ($Why) {
  $entryLines += "  - Why: $Why"
}
if ($Files) {
  $entryLines += "  - Key files:"
  foreach ($f in ($Files -split ',')) {
    $entryLines += "    - ``$($f.Trim())``"
  }
}

$entry = $entryLines -join "`r`n"

# Check if file exists
if (Test-Path $journalFile) {
  $content = Get-Content -Raw -Encoding UTF8 $journalFile
  
  # Check if date heading exists
  $dateHeading = "## $Date"
  if ($content -match "(?m)^## $Date") {
    # Date exists - find where to insert (after the heading, before next heading or EOF)
    $pattern = "(?ms)(## $Date[^\r\n]*\r?\n)(.*?)(?=^## \d{4}-\d{2}-\d{2}|\z)"
    if ($content -match $pattern) {
      $existingBlock = $Matches[0]
      $newBlock = $existingBlock.TrimEnd() + "`r`n`r`n$entry`r`n"
      $content = $content -replace [regex]::Escape($existingBlock), $newBlock
    }
  } else {
    # Date doesn't exist - add new section at the end
    $content = $content.TrimEnd() + "`r`n`r`n$dateHeading`r`n`r`n$entry`r`n"
  }
  
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($journalFile, $content, $utf8NoBom)
  
} else {
  # Create new file
  $projectName = Split-Path -Leaf $RepoRoot
  $header = @"
# Development Journal - $projectName ($month)

## $Date

$entry
"@
  
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($journalFile, ($header -replace "`r?`n", "`r`n"), $utf8NoBom)
}

Write-Host "Added journal entry to: $journalFile" -ForegroundColor Green
Write-Host "  Date: $Date" -ForegroundColor Gray
Write-Host "  Tags: $tagString" -ForegroundColor Gray
Write-Host "  Title: $Title" -ForegroundColor Gray
'@

Write-Utf8NoBom (Join-Path $MemScripts "add-journal-entry.ps1") $addJournalEntry -ForceWrite:$Force

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
Write-Host "Setup complete. (Memory System v3)" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1) Update memo.md with your project's ownership map and current truth" -ForegroundColor White
Write-Host "  2) Indexes auto-rebuild on git commit (or run manually)" -ForegroundColor White
Write-Host ""
Write-Host "Helper scripts:" -ForegroundColor Cyan
Write-Host "  Add lesson:      scripts\memory\add-lesson.ps1 -Title ""..."" -Tags ""..."" -Rule ""...""" -ForegroundColor DarkGray
Write-Host "  Add journal:     scripts\memory\add-journal-entry.ps1 -Tags ""..."" -Title ""...""" -ForegroundColor DarkGray
Write-Host "  Search (SQLite): scripts\memory\query-memory.ps1 -Query ""auth"" -Format AI" -ForegroundColor DarkGray
Write-Host "  Lint:            scripts\memory\lint-memory.ps1" -ForegroundColor DarkGray
Write-Host "  Rebuild index:   scripts\memory\rebuild-memory-index.ps1" -ForegroundColor DarkGray
Write-Host "  Clear session:   scripts\memory\clear-active.ps1" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Remember: Add .cursor/memory/memory.sqlite to .gitignore (generated file)" -ForegroundColor Yellow
Write-Host ""
