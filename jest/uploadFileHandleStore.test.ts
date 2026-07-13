/**
 * Coverage for uploadFileHandleStore (recovery Option C): feature detection, the permission
 * re-grant + re-read path, and a persist -> retrieve -> clear round-trip. jsdom ships neither the
 * File System Access API nor IndexedDB, so both are faked; feature detection is also exercised with
 * them absent (the Firefox/Safari fallback case).
 */
import {
  clearFileHandle,
  clearProjectFileHandles,
  getPersistedFileHandle,
  isFileHandlePersistenceSupported,
  PersistableFileHandle,
  persistFileHandle,
  reReadFileFromHandle,
} from "../app/assets/src/components/views/SampleUploadFlow/components/UploadProgressModal/uploadFileHandleStore";

// --- Minimal in-memory IndexedDB fake (handles are stored as opaque values) -----------------------
class FakeRequest {
  result: unknown;
  onsuccess: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onupgradeneeded: (() => void) | null = null;
  onblocked: (() => void) | null = null;
}
const later = (fn: () => void) => setTimeout(fn, 0);

class FakeCursor {
  constructor(
    private readonly keys: string[],
    private readonly store: Map<string, { projectId: string }>,
    private idx: number,
    private readonly req: FakeRequest,
  ) {}
  delete() {
    this.store.delete(this.keys[this.idx]);
  }
  continue() {
    this.idx += 1;
    this.emit();
  }
  emit() {
    this.req.result = this.idx < this.keys.length ? this : null;
    this.req.onsuccess?.();
  }
}
class FakeIndex {
  constructor(private readonly store: Map<string, { projectId: string }>) {}
  openCursor(range: { only: string }): FakeRequest {
    const req = new FakeRequest();
    const keys = [...this.store.entries()]
      .filter(([, v]) => v.projectId === range.only)
      .map(([k]) => k);
    later(() => new FakeCursor(keys, this.store, 0, req).emit());
    return req;
  }
}
class FakeObjectStore {
  constructor(private readonly store: Map<string, { projectId: string }>) {}
  put(rec: { key: string; projectId: string }): FakeRequest {
    const req = new FakeRequest();
    this.store.set(rec.key, rec);
    req.result = rec.key;
    return req;
  }
  get(key: string): FakeRequest {
    const req = new FakeRequest();
    req.result = this.store.get(key);
    return req;
  }
  delete(key: string): FakeRequest {
    const req = new FakeRequest();
    this.store.delete(key);
    return req;
  }
  index(): FakeIndex {
    return new FakeIndex(this.store);
  }
}
class FakeTransaction {
  oncomplete: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onabort: (() => void) | null = null;
  constructor(private readonly store: Map<string, { projectId: string }>) {
    later(() => this.oncomplete?.());
  }
  objectStore(): FakeObjectStore {
    return new FakeObjectStore(this.store);
  }
}
class FakeDb {
  objectStoreNames = { contains: () => true };
  constructor(private readonly store: Map<string, { projectId: string }>) {}
  transaction(): FakeTransaction {
    return new FakeTransaction(this.store);
  }
  close() {
    /* no-op */
  }
  createObjectStore() {
    return { createIndex: () => undefined };
  }
}

const installFakeEnv = () => {
  const store = new Map<string, { projectId: string }>();
  (global as unknown as { indexedDB: unknown }).indexedDB = {
    open: () => {
      const req = new FakeRequest();
      req.result = new FakeDb(store);
      later(() => req.onsuccess?.());
      return req;
    },
  };
  (global as unknown as { IDBKeyRange: unknown }).IDBKeyRange = {
    only: (v: string) => ({ only: v }),
  };
  // Presence of showOpenFilePicker is the Option C feature gate.
  (window as unknown as { showOpenFilePicker: unknown }).showOpenFilePicker =
    () => Promise.resolve([]);
  return store;
};
const removeEnv = () => {
  delete (global as unknown as { indexedDB?: unknown }).indexedDB;
  delete (window as unknown as { showOpenFilePicker?: unknown })
    .showOpenFilePicker;
};

const fakeHandle = (
  name: string,
  overrides: Partial<PersistableFileHandle> = {},
): PersistableFileHandle => ({
  kind: "file",
  name,
  getFile: async () => new File([new Uint8Array(4)], name),
  ...overrides,
});

afterEach(() => removeEnv());

describe("uploadFileHandleStore feature detection", () => {
  it("is unsupported without showOpenFilePicker (Firefox/Safari fallback case)", () => {
    removeEnv();
    (global as unknown as { indexedDB: unknown }).indexedDB = {};
    expect(isFileHandlePersistenceSupported()).toBe(false);
  });

  it("is supported when both showOpenFilePicker and IndexedDB exist (Chrome/Edge)", () => {
    installFakeEnv();
    expect(isFileHandlePersistenceSupported()).toBe(true);
  });

  it("persist/get degrade to false/null when unsupported", async () => {
    removeEnv();
    expect(await persistFileHandle(1, "k", fakeHandle("f"))).toBe(false);
    expect(await getPersistedFileHandle(1, "k")).toBeNull();
  });
});

describe("uploadFileHandleStore round-trip", () => {
  beforeEach(() => installFakeEnv());

  it("persists a handle, retrieves it, and clears it", async () => {
    const handle = fakeHandle("a_R1.fastq.gz");
    expect(await persistFileHandle(3, "samples/3/a_R1", handle)).toBe(true);

    const got = await getPersistedFileHandle(3, "samples/3/a_R1");
    expect(got).not.toBeNull();
    expect(got?.name).toBe("a_R1.fastq.gz");

    await clearFileHandle(3, "samples/3/a_R1");
    expect(await getPersistedFileHandle(3, "samples/3/a_R1")).toBeNull();
  });

  it("clears all handles for a project, leaving other projects", async () => {
    await persistFileHandle(3, "a", fakeHandle("a"));
    await persistFileHandle(3, "b", fakeHandle("b"));
    await persistFileHandle(4, "c", fakeHandle("c"));

    await clearProjectFileHandles(3);

    expect(await getPersistedFileHandle(3, "a")).toBeNull();
    expect(await getPersistedFileHandle(3, "b")).toBeNull();
    expect(await getPersistedFileHandle(4, "c")).not.toBeNull();
  });
});

describe("reReadFileFromHandle permission re-grant", () => {
  it("returns the File when permission is already granted", async () => {
    const handle = fakeHandle("x", {
      queryPermission: async () => "granted",
    });
    const file = await reReadFileFromHandle(handle);
    expect(file?.name).toBe("x");
  });

  it("requests permission when prompt, then reads on grant", async () => {
    const requestPermission = jest.fn(async () => "granted" as const);
    const handle = fakeHandle("y", {
      queryPermission: async () => "prompt",
      requestPermission,
    });
    const file = await reReadFileFromHandle(handle);
    expect(requestPermission).toHaveBeenCalled();
    expect(file?.name).toBe("y");
  });

  it("returns null when permission is denied", async () => {
    const handle = fakeHandle("z", {
      queryPermission: async () => "prompt",
      requestPermission: async () => "denied",
    });
    expect(await reReadFileFromHandle(handle)).toBeNull();
  });

  it("returns null when the file was moved/deleted (getFile throws)", async () => {
    const handle = fakeHandle("gone", {
      queryPermission: async () => "granted",
      getFile: async () => {
        throw new Error("NotFoundError");
      },
    });
    expect(await reReadFileFromHandle(handle)).toBeNull();
  });
});
