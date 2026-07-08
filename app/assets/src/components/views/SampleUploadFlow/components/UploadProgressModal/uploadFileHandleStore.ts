/**
 * uploadFileHandleStore -- persist FileSystemFileHandles for cross-session upload recovery (Option C).
 *
 * The browser drops a File reference once the page session ends, so after a reload a web app cannot
 * silently re-read a file from disk. The File System Access API (Chrome/Edge) is the exception: a
 * FileSystemFileHandle is structured-cloneable and can be kept in IndexedDB, then re-read later after
 * a single user permission re-grant -- recovering the file across a reload WITHOUT storing gigabytes
 * of bytes (contrast Option B, uploadByteCache, the Firefox/Safari fallback). Once the file is back,
 * the persisted multipart uploadId (uploadResumeState) lets ResumableUpload skip parts already on S3.
 *
 * Chrome/Edge only: feature-detected on `showOpenFilePicker`. Where unsupported (Firefox/Safari),
 * every call degrades to a no-op / null and the caller falls back to Option B. A handle whose file
 * has been moved or deleted since it was persisted will fail the re-read; the caller then prompts a
 * re-select. All storage access is guarded so a failure never breaks the upload path.
 */

const DB_NAME = "czid-upload-filehandles";
const DB_VERSION = 1;
const STORE_NAME = "handles";
const PROJECT_INDEX = "projectId";

// FileSystemFileHandle with the permission methods that ship in Chrome/Edge but are not in the
// standard TS DOM lib yet. Kept local and optional so this compiles without extra @types.
type PermissionState = "granted" | "denied" | "prompt";
interface FsPermissionDescriptor {
  mode?: "read" | "readwrite";
}
export interface PersistableFileHandle {
  kind: "file";
  name: string;
  getFile: () => Promise<File>;
  queryPermission?: (d?: FsPermissionDescriptor) => Promise<PermissionState>;
  requestPermission?: (d?: FsPermissionDescriptor) => Promise<PermissionState>;
}

interface StoredHandleRecord {
  key: string;
  projectId: string;
  s3Key: string;
  handle: PersistableFileHandle;
  name: string;
  updatedAt: number;
}

const handleKey = (projectId: number | string, s3Key: string): string =>
  `${projectId}:${s3Key}`;

/**
 * True only where handles can be both obtained (showOpenFilePicker) and persisted (IndexedDB) --
 * i.e. Chrome/Edge. Everything else falls back to Option B (uploadByteCache).
 */
export const isFileHandlePersistenceSupported = (): boolean => {
  try {
    return (
      typeof window !== "undefined" &&
      "showOpenFilePicker" in window &&
      typeof indexedDB !== "undefined" &&
      indexedDB !== null
    );
  } catch {
    return false;
  }
};

const openDb = (): Promise<IDBDatabase | null> => {
  if (!isFileHandlePersistenceSupported()) return Promise.resolve(null);
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
// failure) so a storage error can never reject into the upload path.
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
 * Persist a file handle for a sample file so a later session can re-read it. Best-effort: no-ops
 * (returns false) when unsupported or on any storage failure.
 */
export const persistFileHandle = async (
  projectId: number | string,
  s3Key: string,
  handle: PersistableFileHandle,
): Promise<boolean> => {
  const db = await openDb();
  if (!db) return false;
  try {
    const record: StoredHandleRecord = {
      key: handleKey(projectId, s3Key),
      projectId: String(projectId),
      s3Key,
      handle,
      name: handle.name ?? "",
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

// Retrieve a persisted handle (or null). The handle still needs a permission re-grant before its
// bytes can be read -- see reReadFileFromHandle.
export const getPersistedFileHandle = async (
  projectId: number | string,
  s3Key: string,
): Promise<PersistableFileHandle | null> => {
  const db = await openDb();
  if (!db) return null;
  try {
    const record = await runRequest<StoredHandleRecord>(db, "readonly", store =>
      store.get(handleKey(projectId, s3Key)),
    );
    return record?.handle ?? null;
  } finally {
    db.close();
  }
};

export const clearFileHandle = async (
  projectId: number | string,
  s3Key: string,
): Promise<void> => {
  const db = await openDb();
  if (!db) return;
  try {
    await runRequest(db, "readwrite", store =>
      store.delete(handleKey(projectId, s3Key)),
    );
  } finally {
    db.close();
  }
};

/**
 * Clear every persisted handle for a project. Called on successful completion and on project change
 * so handles never linger.
 */
export const clearProjectFileHandles = async (
  projectId: number | string,
): Promise<void> => {
  const db = await openDb();
  if (!db) return;
  try {
    await new Promise<void>(resolve => {
      try {
        const tx = db.transaction(STORE_NAME, "readwrite");
        const store = tx.objectStore(STORE_NAME);
        const cursorReq = store
          .index(PROJECT_INDEX)
          .openCursor(IDBKeyRange.only(String(projectId)));
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

/**
 * Re-read the file from a persisted handle, requesting read permission first (the one-click
 * re-grant). Returns the File, or null when permission is denied or the file was moved/deleted since
 * it was persisted (the caller should then prompt a re-select).
 */
export const reReadFileFromHandle = async (
  handle: PersistableFileHandle,
): Promise<File | null> => {
  try {
    const descriptor: FsPermissionDescriptor = { mode: "read" };
    let state: PermissionState = "granted";
    if (handle.queryPermission) {
      state = await handle.queryPermission(descriptor);
    }
    if (state !== "granted" && handle.requestPermission) {
      state = await handle.requestPermission(descriptor);
    }
    if (state !== "granted") return null;
    return await handle.getFile();
  } catch {
    // Permission dismissed, or the file no longer exists at its original path.
    return null;
  }
};

/**
 * Open the File System Access picker and return the selected files paired with their handles, for a
 * caller that wants to enable cross-session recovery (Option C). Returns [] when unsupported or when
 * the user cancels. This is the adoption point that replaces a plain file <input> where handles are
 * wanted; the existing drag-and-drop input remains the universal fallback.
 */
export const pickFilesWithHandles = async (): Promise<
  Array<{ handle: PersistableFileHandle; file: File }>
> => {
  if (!isFileHandlePersistenceSupported()) return [];
  try {
    const picker = (
      window as unknown as {
        showOpenFilePicker: (opts?: {
          multiple?: boolean;
        }) => Promise<PersistableFileHandle[]>;
      }
    ).showOpenFilePicker;
    const handles = await picker({ multiple: true });
    const results: Array<{ handle: PersistableFileHandle; file: File }> = [];
    for (const handle of handles) {
      try {
        results.push({ handle, file: await handle.getFile() });
      } catch {
        // Skip a handle we cannot read right now.
      }
    }
    return results;
  } catch {
    // User cancelled the picker, or it is unavailable.
    return [];
  }
};
