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