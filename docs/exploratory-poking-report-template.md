# Exploratory "poking" run — report

> Fill one copy per run. Protocol: `docs/EXPLORATORY-POKING-PROTOCOL.md` (#465).

## Header

| Field | Value |
| --- | --- |
| Date (UTC) | `YYYY-MM-DD HH:MM` |
| Environment | dev / staging / prod (read-only) |
| App version / build hash | |
| Driver | Claude agent (Chrome MCP + API probes) |
| Test account | `<email>` |
| Account role | regular / admin |
| Overall verdict | GREEN / DEGRADED / RED |

## Summary

- Surfaces tested: `N`
- PASS: `N` · DEGRADED: `N` · FAIL: `N` · BLOCKED: `N` · N/A: `N`
- **New FAILs since last run:** `...`
- **Promotion recommendation:** GO / NO-GO — `<one line why>`

## Surface results

| # | Surface | UI | API | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| 3.1 | Auth & session | | | | |
| 3.2 | Project + sample list | | | | |
| 3.3 | Upload ⭐ | | | | |
| 3.4 | Sample report view | | | | |
| 3.5 | Downloads (single + bulk) ⭐ | | | | |
| 3.6 | Heatmap | | | | |
| 3.7 | AMR | | | | |
| 3.8 | Consensus Genome | | | | |
| 3.9 | Phylo tree | | | | |
| 3.10 | Admin | | | | |
| 3.11 | Cross-cutting sweeps | | | | |

## Findings (one block per DEGRADED/FAIL)

### F-1 · `<short title>` · [FAIL|DEGRADED] · surface 3.x

- **What happened:** `<observed vs expected>`
- **Repro:** `<steps / URL>`
- **Request:** `<method + endpoint>`
- **HTTP status:** `<code>`
- **Response / error:** `<body snippet or console/network error>`
- **UI looked fine but API failed?** yes / no  ← the bulk-download-bug tell
- **Evidence:** `<screenshot path, console dump, network dump>`
- **Filed as:** `<issue link>` (link to #382 / reliability epic)

## Cross-cutting sweep results

- **Console errors at rest:** `<per-surface list>`
- **Background 4xx/5xx requests:** `<list>`
- **Deep-link failures:** `<list>`
