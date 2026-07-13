# Claude-driven exploratory "poking" protocol

**Ticket:** #465 (child rollup under the reliability epic #462). Feeds #382 (Sentry cleanup).

A repeatable, agent-driven exploratory-testing protocol. A Claude agent drives the
**deployed** app — browser via the Chrome MCP + direct API/GraphQL probes — to
systematically exercise every user-facing surface and report **what's broken vs
working**. This is the same technique that found and confirmed the bulk-download bug
(a silent local S3 upload failure that green unit tests never caught).

It **complements** the automated suites (rspec/jest/Playwright): those assert known
contracts; this hunts for integration/UX breakage that tests miss — the "unknown
unknowns" — and produces a structured, comparable report each run.

> **Scope of this doc:** the protocol and report template only. **Running it live is
> a separate exercise** that needs the Chrome MCP pointed at a deployed environment
> and the appropriate credentials. Do not run against prod without sign-off. Prefer
> **dev** or **staging**; treat any data you create as disposable.

---

## 0. Operating rules (read first)

1. **Environment.** Default target is **dev**, then **staging**. Never mutate prod
   data (no uploads/deletes) without explicit sign-off; read-only probing of prod is
   the most you should do unprompted.
2. **Identity.** Use a dedicated test account, not a real user's. Note the account +
   role (regular vs admin) in the report header — surfaces differ by role.
3. **Two lenses, always.** For each surface, drive it **through the browser** (what a
   user sees) **and** hit the underlying **API/GraphQL** directly. A page can render
   fine while the API 500s a sub-request (this is exactly how the bulk-download bug
   hid). Compare the two.
4. **Capture evidence.** For every FAIL/DEGRADED: the URL, the exact request, the
   HTTP status, the response body (or console/network error), and a screenshot.
   Attach the browser **console errors** and **failed network requests** — the Chrome
   MCP exposes both.
5. **Classify, don't fix.** This protocol produces a report. Do **not** patch app code
   here. File findings; link them to #382 / the reliability epic.
6. **Determinism.** Follow the surfaces in the order below so runs are comparable.
   Fill the report template for **every** surface, including the ones that pass.

### Result classification

| Status | Meaning |
| --- | --- |
| **PASS** | Surface works end-to-end via both UI and API. |
| **DEGRADED** | Renders/responds but with errors (console errors, slow, partial data, broken sub-feature, wrong-but-non-blocking result). |
| **FAIL** | Core action is broken (page won't load, action 500s, data missing, download corrupt/empty). |
| **BLOCKED** | Couldn't test (missing perms, missing data, dependency down). Note why. |
| **N/A** | Surface not present in this environment / not enabled for this account. |

---

## 1. Tooling

- **Browser:** Chrome MCP (`mcp__claude-in-chrome__*`) — navigate, read_page,
  computer (click/type), `read_console_messages`, `read_network_requests`,
  `file_upload`, `form_input`.
- **API/GraphQL:** direct HTTP. The app exposes a GraphQL endpoint (`/graphql`) plus
  REST controllers (see `app/controllers/`). Grab the session cookie / auth token from
  the browser session and replay requests with `curl`/fetch to probe the API layer
  independently of the UI.
- **Evidence:** screenshots + saved console/network dumps per finding.

---

## 2. Pre-flight

1. Confirm the target environment + version (footer/build hash, or `/health` if present).
2. Log in with the test account. Confirm the landing/discovery view renders.
3. Open the browser console + network panels (via the MCP) so errors are captured from
   the first click.
4. Note baseline: any errors **already** on screen at rest? Record them — they colour
   everything after.

---

## 3. Surface-by-surface probes

Work top to bottom. Each surface: **UI probe → API probe → expected result → classify**.

### 3.1 Auth & session
- **UI:** log in, log out, log back in. Hit a deep-linked authed URL while logged out
  → expect redirect to login, then back. Try an admin-only URL as a regular user →
  expect denial, not a 500.
- **API:** call an authed endpoint with (a) a valid token, (b) no token, (c) an expired
  token. Expect 200 / 401 / 401 respectively — **not** 500, and never data leakage.
- **Expected:** clean redirects, correct 401/403s, no stack traces.

### 3.2 Project + sample list (discovery view)
- **UI:** load the discovery/project view. Filters, search, sort, pagination. Open a
  project. Switch tabs (samples / visualizations).
- **API:** the list/query endpoint (GraphQL discovery query or REST). Check counts on
  the page match the API's `total`. Page 2. An empty filter (no results) should render
  empty state, not error.
- **Expected:** counts match, filters narrow results, no console errors, no slow (>5s)
  list loads.

### 3.3 Upload  ⭐ (where the known bug lived)
- **UI:** start a sample upload (local file). Watch it through validation → S3 upload →
  pipeline kickoff. **Pause/resume** if the UI offers it (resumable upload). Try a
  metadata CSV. Try an intentionally bad file (wrong extension) → expect a clear
  validation error, not a hang.
- **API:** watch the **network tab** during upload — the S3 PUT/multipart requests are
  where the bulk-download-class bug hid (the page looked fine; the S3 write silently
  failed). Confirm every upload-part request returns 2xx and the final
  "mark complete" call succeeds. Then confirm the sample actually appears server-side
  (list/query it back).
- **Expected:** file lands in S3 (verify via a follow-up read, not just the UI's
  optimistic "done"), sample row created, pipeline dispatched. **A green UI is not
  proof — read it back.**

### 3.4 Sample report view
- **UI:** open a completed sample's report. Taxon table renders, filters/thresholds
  apply, tooltips work, sorting works. Toggle NT/NR. Coverage viz / detail drawers open.
- **API:** the report-data endpoint returns the taxon rows the table shows. Spot-check
  a metric value in the UI against the API payload. A **loading spinner that never
  resolves** = FAIL (check the network request that's hanging/erroring).
- **Expected:** report populates, numbers match API, no infinite spinners.

### 3.5 Downloads (single + bulk)  ⭐
- **UI:** from a report, download a single result file. From the sample list, select
  several samples → **bulk download** (the exact surface of the known bug) → pick a
  download type → generate → wait → download the archive.
- **API:** trace the bulk-download creation call (GraphQL mutation / REST) and the
  eventual signed-URL/redirect. **Actually fetch the artifact** and confirm it's
  non-empty and well-formed (unzip it / check the byte size) — an empty or 0-byte
  archive with a 200 is the classic silent failure.
- **Expected:** archive downloads, is non-empty, contains the expected files. Verify
  the bytes, not just the click.

### 3.6 Heatmap
- **UI:** select multiple samples → open the taxon heatmap. It renders cells, the axis
  labels populate, hovering shows values, filters/metric-switch re-render. Save/share
  if available.
- **API:** the heatmap data endpoint (ElasticSearch-backed) returns a populated matrix.
  An all-blank or all-NaN heatmap with a 200 = DEGRADED/FAIL — check the data call.
- **Expected:** populated matrix, interactive, values match the API.

### 3.7 AMR (antimicrobial resistance)
- **UI:** open an AMR result/report. The gene/drug table renders, metrics populate,
  the AMR heatmap (if present) draws. Download the AMR results.
- **API:** the AMR report-data + metrics endpoints return rows. Cross-check a metric.
- **Expected:** table populates, download works, numbers match.

### 3.8 Consensus Genome (CG)
- **UI:** open a CG workflow run report. Coverage viz renders, quality metrics show,
  the consensus FASTA is downloadable. Multi-sample CG overview (if present) loads.
- **API:** CG coverage + metrics + concat endpoints respond; the FASTA download is
  non-empty and looks like FASTA.
- **Expected:** report + coverage render, FASTA downloads and is valid.

### 3.9 Phylo tree
- **UI:** open / create a phylo tree visualization. It renders, nodes are interactive.
- **API:** the tree data endpoint responds; a creation kicks off a run.
- **Expected:** tree renders or creation dispatches cleanly.

### 3.10 Admin surfaces (admin account only)
- **UI:** admin dashboard, user management, feature-flag toggles, any admin-only
  reports. Load each; don't mutate unless the env is disposable.
- **API:** admin endpoints require admin; confirm a regular account is **denied**
  (403), not served (data-leak) and not 500'd.
- **Expected:** admin pages load for admins, hard-denied for non-admins.

### 3.11 Cross-cutting sweeps (run last)
- **Console error sweep:** revisit each surface; any surface throwing console errors at
  rest → log it (feeds #382 Sentry cleanup).
- **Network failure sweep:** any 4xx/5xx background request on any page → log it, even
  if the page "looks fine" (this is the bulk-download-bug lesson: UIs mask API failures).
- **Deep-link sweep:** paste a handful of deep-linked URLs (specific sample, specific
  viz) into a fresh tab → they should resolve, not error.

---

## 4. Report template

Copy `docs/exploratory-poking-report-template.md` for each run and fill it in. One row
per surface, plus a findings list with evidence. The header block makes runs
comparable over time and pre-release.

---

## 5. Cadence & when to run

- **Pre-release / prod-promotion:** run the full protocol against staging before
  promoting. A new FAIL is a promotion blocker.
- **On a cadence:** weekly against dev/staging to catch drift.
- **After a big change:** targeted run of the affected surfaces.

The output (the filled report) is the deliverable — attach it to the release / the
relevant ticket, and file each FAIL/DEGRADED as its own issue linked to #382 and the
reliability epic.
