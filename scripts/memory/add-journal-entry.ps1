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

if (-not (Test-Path $JournalDir)) {
  New-Item -ItemType Directory -Force -Path $JournalDir | Out-Null
}

$month = $Date.Substring(0, 7)
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

if (Test-Path $journalFile) {
  $content = Get-Content -Raw -Encoding UTF8 $journalFile
  
  $dateHeading = "## $Date"
  if ($content -match "(?m)^## $Date") {
    # Date exists - append to that section
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
  
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($journalFile, $content, $enc)
  
} else {
  # Create new file
  $projectName = Split-Path -Leaf $RepoRoot
  $header = @"
# Development Journal - $projectName ($month)

## $Date

$entry
"@
  
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($journalFile, ($header -replace "`r?`n", "`r`n"), $enc)
}

Write-Host "Added journal entry to: $journalFile" -ForegroundColor Green
Write-Host "  Date: $Date" -ForegroundColor Gray
Write-Host "  Tags: $tagString" -ForegroundColor Gray
Write-Host "  Title: $Title" -ForegroundColor Gray