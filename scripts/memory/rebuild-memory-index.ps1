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