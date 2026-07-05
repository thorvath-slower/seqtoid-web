# Failed-upload recovery — design & options

## Problem

When a local sample upload fails, the recovery flow was painful: the failure
screen's primary action sent the user to the project page, which tore down the
upload session and forced them to **redo the entire upload wizard** to re-send the
same files. For multi-GB genomic data that is slow, error-prone, and not
customer-friendly.

We want a failed upload to be recoverable with as little friction as possible —
ideally one click, without re-selecting files or repeating the wizard.

## The core browser constraint

Browsers do **not** let a web app silently re-read a file from disk. When a user
picks a file you receive a `File` object that is valid **only for that page
session**. Navigate away, reload, or close the tab and that reference is gone — the
browser will not hand it back without either the user re-selecting the file or one
of the persistence mechanisms below.

That splits recovery into two very different problems:

| Class | Situation | Are the files still available? |
|-------|-----------|-------------------------------|
| **Same-session** | Upload failed, user has not navigated away | ✅ Yes — the `File` objects are still in JS memory |
| **Cross-session** | User navigated away / reloaded / closed the tab | ❌ No — the references are gone |

## Options

### A — Retry in place (keep the session) ✅ implemented
On failure, keep the upload modal open and make **Retry** the primary action
instead of "Go to Project". The `File` objects are still in memory, so retry is one
click with no re-selection and no wizard. Cheapest, most reliable, no storage, works
in **every** browser. Solves the entire same-session class.

### B — Cache file *bytes* in IndexedDB ⏳ held (ticketed)
IndexedDB (unlike localStorage) can store `File`/`Blob` objects, so we could stash
the data and re-upload after a reload with no re-selection. **But** genomic files are
routinely multiple GB: writing them to IndexedDB is slow, consumes disk, hits browser
quota/eviction, and leaves sample data sitting in browser storage (a privacy
consideration). Only viable **size-gated** (e.g. cache files under ~100–200 MB; larger
fall back to re-select). Works in all modern browsers.

### C — Persist a file *handle*, not the bytes ⏳ held (ticketed)
The File System Access API lets us keep a `FileSystemFileHandle` in IndexedDB and
re-read the file later with a one-click permission re-grant — recovering the file
across reloads **without** storing gigabytes. Best storage/UX trade-off, but
Chrome/Edge only (see browser matrix), and the file must still exist at its original
path.

### D — Resume the *transfer*, not just the upload ✅ implemented (already wired)
`ResumableUpload` + `uploadResumeState` already persist the multipart `uploadId` and,
on retry/resume, page through `ListParts` and skip parts whose bytes match the
recorded SHA256 — so only the missing bytes are re-sent, not the whole file. This is
the efficiency layer beneath A/B/C: once you have the file back, you never re-upload
data already on S3. (It does not help a failure that sent zero bytes, e.g. a
credentials error — there is nothing to resume — but it matters for big-file network
drops.)

## Firefox / Safari — how cross-session recovery degrades

Option C depends on the File System Access API, which is **not** available in Firefox
or Safari. The strategy is progressive enhancement driven by feature detection, so
every browser gets the best recovery it can support:

```
Same-session failure ............ Option A + D   → all browsers (Chrome, Edge, Firefox, Safari)
Cross-session, Chrome/Edge ....... Option C + D   → recover file via persisted handle (1 permission click)
Cross-session, Firefox/Safari .... Option B + D   → recover file from IndexedDB bytes (size-gated)
Cross-session, file too large .... graceful re-select prompt (deep-link back into the wizard, prefilled)
```

Feature detection (illustrative):

```ts
const canPersistHandle = "showOpenFilePicker" in window; // Chrome/Edge
// C where available; else B (size-gated); else prompt to re-select.
```

| Browser | File System Access (C) | IndexedDB bytes (B) | Same-session (A+D) |
|---------|:----------------------:|:-------------------:|:------------------:|
| Chrome / Edge | ✅ | ✅ | ✅ |
| Firefox | ❌ | ✅ | ✅ |
| Safari | ❌ | ✅ | ✅ |

So Firefox/Safari never lose recovery — they fall back to **B (size-gated)** for
cross-session, and re-select for files too large to cache. A + D already cover the
common case (retry without leaving) everywhere.

## Status

| Option | State |
|--------|-------|
| **A** — retry-in-place (Retry primary on failure) | ✅ shipped |
| **D** — multipart transfer resume on retry | ✅ shipped (was already wired: `resumableUpload.ts` + `uploadResumeState.ts`) |
| **C** — persisted file handles (Chrome/Edge) | ⏳ ticketed follow-up |
| **B** — IndexedDB byte cache (size-gated; Firefox/Safari fallback) | ⏳ ticketed follow-up |

## Recommended sequencing

1. **A + D now** — one-click same-session recovery, every browser. (done)
2. **C** — cross-session recovery for Chrome/Edge via persisted handles.
3. **B** — size-gated IndexedDB byte cache as the universal fallback (covers
   Firefox/Safari cross-session), with a re-select prompt for oversized files.
