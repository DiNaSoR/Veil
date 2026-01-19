---
id: L-001
title: Use single-quoted here-strings for embedded scripts
status: Active
tags: [PowerShell, Build, DX]
introduced: 2026-01-20
applies_to:
  - memory.ps1
  - scripts/**/*.ps1
rule: Use @'...'@ (single-quoted) for embedded scripts to prevent variable expansion.
---

# L-001 - Use single-quoted here-strings for embedded scripts

## Symptom

PowerShell script fails with "variable '$Path' cannot be retrieved because it has not been set" when writing embedded scripts.

## Root cause

Double-quoted here-strings (`@"..."@`) expand variables. If the embedded script contains `$Path` and `Set-StrictMode -Version Latest` is enabled, PowerShell tries to expand the variable before assignment.

## Wrong approach (DO NOT REPEAT)

- Using `@"..."@` for embedded PowerShell/Python scripts
- Trying to escape every `$` character manually

## Correct approach

- Use `@'...'@` (single-quoted here-strings) for any embedded script content
- Single-quoted here-strings treat content as literal text

```powershell
# Good
$script = @'
$Path = "some value"
Write-Host $Path
'@

# Bad - will try to expand $Path
$script = @"
$Path = "some value"
Write-Host $Path
"@
```

## References

- Files: `memory.ps1`
- Journal: `journal/2026-01.md#2026-01-20`
