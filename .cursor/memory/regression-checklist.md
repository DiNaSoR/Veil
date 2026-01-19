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