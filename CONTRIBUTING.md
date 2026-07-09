# Contributing -- PR and ticket conventions

Canonical, binding change-management convention for this repo (and the doctrine we
hold to across all seqtoid platform repos and for all agents/devs). Tracked in
**CZID-108**. If you read only one process doc before opening a PR, read this one.

> **TL;DR:** Tiny, single-purpose PRs you can read in one sitting. One ticket, one
> concern, one PR. Prove it works locally in Docker before you push -- CI is the
> final stamp, not how you find out if it works. Never bundle work into a blob.

For the mechanics of *how* to build and test (commands, local Docker harness), see
[`DEVELOPMENT.md`](DEVELOPMENT.md); for frontend style see
[`DEV_GUIDELINES.md`](DEV_GUIDELINES.md). This doc is about PR *shape*, *scope*, and
*traceability*.

---

## Why this exists (the pain we are fixing)

Early in the overhaul we shipped huge bundled branches -- a 678-file OpenTofu
conversion, a 12-commit Postgres migration. The damage:

1. **Unreviewable.** No human can meaningfully review hundreds/thousands of lines.
2. **Cherry-pick hell.** A real fix gets buried in a branch full of unrelated work,
   so extracting it means cherry-picking out of a blob.
3. **Lost provenance.** You cannot answer "where did this specific change come from."
4. **CI-as-dev-loop.** Pushing to let CI tell us whether code runs is slow, noisy,
   and inflates PR history with "fix CI" churn.

Small PRs + local validation fix all four. This is non-negotiable going forward.

---

## The rules

### 1. One ticket -> one concern -> one PR
No kitchen-sink branches. If a PR description needs the word "also", it is two PRs.
A reviewer should understand the *single* thing a PR does.

### 2. PR size budget: about 300 lines of meaningful change or fewer
Exclude generated files from the count: lockfiles (`Gemfile.lock`, `.terraform.lock.hcl`),
`db/schema.rb`, relay/`*.graphql.ts`, terraform-docs READMEs. Over budget -> split into
**stacked PRs**, each independently reviewable and merged in order.

### 3. Size the *ticket* to fit the PR -- decompose epics first
Estimate effort on the ticket. If the work cannot land in one budget-sized PR, the
ticket is an **epic**: break it into child tickets **before** starting work.
Exemplar: CZID-100 (171 test failures) -> CZID-103 through 107, one small PR each.

### 4. Traceability -- always answer "where did this come from"
- **Branch:** `cat-<NNN>-short-slug` (e.g. `bug-111-puma-rack3`, `czid-108-conventions`).
- **Every commit subject** prefixed with the ticket: `bug-111: ...`.
- **PR title** carries the ticket; **PR body links** the tracking issue.

### 5. No bundling, ever
A fix never rides inside a branch loaded with other changes -- so we never have to
cherry-pick it back out. Unrelated work = a separate ticket + branch + PR.

### 6. Dependent work = stacked PRs, not one big branch
If B needs A, open A as its own small PR; branch B off A; keep them reviewable in order.

### 7. Rework until it works -- do not paper over
If something is broken, fix it properly and prove it. No skips, no "good enough",
no leaving a known-broken thing for CI to flag.

### 8. Validate LOCALLY in Docker BEFORE pushing -- CI is the final gate
- Get green on the **local harness** first (`make ci-local` / `bin/ci-local`).
- **Do NOT use CI to discover whether code works.** CI is the *final confirmation
  pass*, expected to pass first try. Iterating via CI pushes is the anti-pattern we
  are eliminating.

### 9. The local harness must mirror the REAL build/runtime environment
- Match what actually ships, not the convenient local default. For seqtoid-web that is
  **amd64 `ruby:3.3.6` (Debian bookworm)** -- the CI job runs in `container: ruby:3.3.6`
  and the app deploys that same image. Not the runner host OS (ubuntu), not native
  Apple Silicon (arm64) -- both misrepresent the build.
- On Apple Silicon, emulate amd64 (`platform: linux/amd64`). Slower, but faithful.
- **Single source of truth:** local and CI run the *same* script (e.g. `bin/ci-test`)
  so they can never drift.

### 10. Tests-first where behavior matters
For correctness-critical work (e.g. the Postgres/MySQL parity and scientific paths),
the test that proves the change is correct lands with or before the change.

### 11. ASCII-only code comments
Keep code comments ASCII: use `--` for an em-dash, `->` for an arrow, and spell out
symbols (`>=`, `section`) instead of non-ASCII glyphs. Non-ASCII comments have
tripped Excel-based handoffs and RuboCop's `Style/AsciiComments`; keep the diff clean.

---

## The task loop (do this for every ticket)
1. Move the ticket to **In Progress** *before* starting (so WIP is visible).
2. Make the change -- small, single-concern.
3. `make ci-local` -> green locally in Docker.
4. Open the **small PR** (ticket ID in branch/commits/title; link the issue).
5. CI runs as the **final gate** (should pass first try).
6. On merge: **close the ticket**, then **open the next** (In Progress).

---

## Reviewer's bill of rights
A reviewer is entitled to: read the PR end-to-end in one sitting; understand the single
thing it does; trace it to a ticket; and see it was validated locally before arriving.
If any of those is false, the PR is too big or mis-scoped -- **send it back to be split.**

## Handling inherited big work
Some already-built branches are large/atomic (the conversion, the migration). Do not add
to a blob: when touching one, peel the next change off as its own small PR, and decompose
the remainder into tickets. New work always follows the rules above.
