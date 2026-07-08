/**
 * uploadByteCache -- size-gated IndexedDB cache of upload file bytes (recovery Option B).
 *
 * Cross-session upload recovery needs the original File back after a reload, but the browser
 * discards a File reference once the page session ends. On Chrome/Edge the File System Access API
 * (Option C, uploadFileHandleStore) recovers the file via a persisted handle without storing bytes.
 * Firefox and Safari have no File System Access API, so their only cross-session fallback is to
 * cache the bytes themselves. IndexedDB (unlike localStorage) can store File/Blob objects, so we
 * stash them here and re-instantiate ResumableUpload after a reload with the cached data. The
 * persisted multipart uploadId (uploadResumeState) then lets ResumableUpload skip parts already on
 * S3, so only the missing bytes are re-sent.
 *
 * MUST be size-gated: genomic FASTQ files are routinely multiple GB, and writing those to IndexedDB
 * is slow, consumes disk, blows the browser storage quota, and leaves sample data sitting in browser
 * storage (a privacy concern). So only files under MAX_CACHEABLE_BYTES are cached; larger files fall
 * back to a graceful re-select prompt (handled by the caller). The cache is cleared on successful
 * completion and on project change so bytes never linger.
 *
 * Everything is best-effort and feature-detected: if IndexedDB is unavailable, disabled (private
 * mode), or the write fails (quota), the API degrades to "nothing cached" rather than breaking the
 * upload.
 */

// Cache only files at or below this size. Genomic files above it fall back to re-select. ~150 MB is
// a conservative default well under typical browser per-origin quotas while still covering small
// samples and non-FASTQ inputs. Tunable; kept a round number for clarity.
export const MAX_CACHEABLE_BYTES = 150 * 1024 * 1024;

const DB_NAME = "czid-upload-bytecache";
const DB_VERSION = 1;
const STORE_NAME = "files";
const PROJECT_INDEX = "projectId";

export interface CachedUploadFile {
  // Composite primary key: `${projectId}:${s3Key}`.
  key: string;
  projectId: string;
  s3Key: string;
  blob: Blob;
  name: string;
  type: string;
  size: number;
  updatedAt: number;
}

const cacheKey = (projectId: number | string, s3Key: string): string =>
  `${projectId}:${s3Key}`;

// Feature detection: IndexedDB must exist (absent in some private-mode contexts and old browsers).
export const isByteCacheSupported = (): boolean => {
  try {
    return typeof indexedDB !== "undefined" && indexedDB !== null;
  } catch {
    // Accessing indexedDB can itself throw (e.g. sandboxed iframes).
    return false;
  }
};

// The size gate: a file is cacheable only when caching is supported and it is small enough that
// stashing it in IndexedDB is reasonable. Larger files fall back to re-select.
export const canCacheFile = (size: number): boolean =>
  isByteCacheSupported() && size >= 0 && size <= MAX_CACHEABLE_BYTES;

const openDb = (): Promise<IDBDatabase | null> => {
  if (!isByteCacheSupported()) return Promise.resolve(null);
  return new Promise(resolve => {
    try {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          const store = db.createObjectStore(STORE_NAME, { keyPath: "key" });
          store.createIndex(PROJECT_INDEX, "projectId", { unique: false });
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => resolve(null);
      request.onblocked = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
};

// Run a single-store transaction to completion, resolving with the request result (or null on any
// failure). Kept tiny and defensive so a storage error can never reject into the upload path.
const runRequest = <T>(
  db: IDBDatabase,
  mode: IDBTransactionMode,
  op: (store: IDBObjectStore) => IDBRequest | undefined,
): Promise<T | null> =>
  new Promise(resolve => {
    try {
      const tx = db.transaction(STORE_NAME, mode);
      const store = tx.objectStore(STORE_NAME);
      const request = op(store);
      tx.oncomplete = () => resolve((request?.result as T | undefined) ?? null);
      tx.onerror = () => resolve(null);
      tx.onabort = () => resolve(null);
    } catch {
      resolve(null);
    }
  });

/**
 * Cache a file's bytes for later cross-session recovery. No-ops (returns false) when caching is
 * unsupported or the file exceeds the size gate, so the caller can fall back to a re-select prompt.
 * Best-effort: a quota/write failure also resolves false rather than throwing.
 */
export const cacheUploadFile = async (
  projectId: number | string,
  s3Key: string,
  file: Blob & { name?: string },
): Promise<boolean> => {
  if (!canCacheFile(file.size)) return false;
  const db = await openDb();
  if (!db) return false;
  try {
    const record: CachedUploadFile = {
      key: cacheKey(projectId, s3Key),
      projectId: String(projectId),
      s3Key,
      blob: file,
      name: file.name ?? "",
      type: file.type ?? "",
      size: file.size,
      updatedAt: Date.now(),
    };
    const ok = await runRequest<IDBValidKey>(db, "readwrite", store =>
      store.put(record),
    );
    return ok !== null;
  } finally {
    db.close();
  }
};

/**
 * Recover a previously cached file. Returns a File (reconstructed with its original name/type) or
 * null when nothing is cached / caching is unsupported.
 */
export const getCachedUploadFile = async (
  projectId: number | string,
  s3Key: string,
): Promise<File | null> => {
  const db = await openDb();
  if (!db) return null;
  try {
    const record = await runRequest<CachedUploadFile>(db, "readonly", store =>
      store.get(cacheKey(projectId, s3Key)),
    );
    if (!record || !record.blob) return null;
    try {
      return new File([record.blob], record.name, {
        type: record.type,
        lastModified: record.updatedAt,
      });
    } catch {
      // Some environments lack the File constructor; the raw Blob still carries the bytes, but the
      // upload flow expects a File, so treat that as "not recoverable" here.
      return null;
    }
  } finally {
    db.close();
  }
};

// Remove a single cached file (e.g. once its upload completes).
export const clearCachedUploadFile = async (
  projectId: number | string,
  s3Key: string,
): Promise<void> => {
  const db = await openDb();
  if (!db) return;
  try {
    await runRequest(db, "readwrite", store =>
      store.delete(cacheKey(projectId, s3Key)),
    );
  } finally {
    db.close();
  }
};

/**
 * Clear every cached file for a project. Called on successful completion and on project change so
 * cached sample bytes never linger in browser storage longer than a resume could need them.
 */
export const clearProjectByteCache = async (
  projectId: number | string,
): Promise<void> => {
  const db = await openDb();
  if (!db) return;
  try {
    await new Promise<void>(resolve => {
      try {
        const tx = db.transaction(STORE_NAME, "readwrite");
        const store = tx.objectStore(STORE_NAME);
        const index = store.index(PROJECT_INDEX);
        const cursorReq = index.openCursor(IDBKeyRange.only(String(projectId)));
        cursorReq.onsuccess = () => {
          const cursor = cursorReq.result;
          if (cursor) {
            cursor.delete();
            cursor.continue();
          }
        };
        tx.oncomplete = () => resolve();
        tx.onerror = () => resolve();
        tx.onabort = () => resolve();
      } catch {
        resolve();
      }
    });
  } finally {
    db.close();
  }
};
