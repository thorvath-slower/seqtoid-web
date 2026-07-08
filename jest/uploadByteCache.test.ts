/**
 * Coverage for uploadByteCache (recovery Option B): the size gate, feature detection, and a
 * cache -> recover -> clear round-trip. jsdom ships no IndexedDB, so a compact in-memory fake stands
 * in for the store; the pure gating logic is also exercised with IndexedDB absent.
 */
import {
  cacheUploadFile,
  canCacheFile,
  clearCachedUploadFile,
  clearProjectByteCache,
  getCachedUploadFile,
  isByteCacheSupported,
  MAX_CACHEABLE_BYTES,
} from "../app/assets/src/components/views/SampleUploadFlow/components/UploadProgressModal/uploadByteCache";

// --- Minimal in-memory IndexedDB fake -------------------------------------------------------------
// Supports exactly the surface uploadByteCache uses: open (with an existing store), a readwrite/
// readonly transaction with oncomplete, object-store put/get/delete, and an index cursor walk.
class FakeRequest<T = unknown> {
  result: T | undefined;
  onsuccess: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onupgradeneeded: (() => void) | null = null;
  onblocked: (() => void) | null = null;
}

const later = (fn: () => void) => setTimeout(fn, 0);

class FakeCursor {
  constructor(
    private readonly keys: string[],
    private readonly store: Map<string, unknown>,
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
    if (this.idx < this.keys.length) {
      this.req.result = this;
    } else {
      this.req.result = null;
    }
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

const installFakeIndexedDb = () => {
  const store = new Map<string, { projectId: string }>();
  (global as unknown as { indexedDB: unknown }).indexedDB = {
    open: () => {
      const req = new FakeRequest();
      req.result = new FakeDb(store) as unknown;
      later(() => req.onsuccess?.());
      return req;
    },
  };
  (global as unknown as { IDBKeyRange: unknown }).IDBKeyRange = {
    only: (v: string) => ({ only: v }),
  };
  return store;
};

const removeIndexedDb = () => {
  delete (global as unknown as { indexedDB?: unknown }).indexedDB;
};

afterEach(() => removeIndexedDb());

describe("uploadByteCache feature detection and size gate", () => {
  it("reports unsupported when IndexedDB is absent (jsdom / private mode)", () => {
    removeIndexedDb();
    expect(isByteCacheSupported()).toBe(false);
    expect(canCacheFile(1)).toBe(false);
  });

  it("gates on size when supported", () => {
    installFakeIndexedDb();
    expect(isByteCacheSupported()).toBe(true);
    expect(canCacheFile(0)).toBe(true);
    expect(canCacheFile(MAX_CACHEABLE_BYTES)).toBe(true);
    expect(canCacheFile(MAX_CACHEABLE_BYTES + 1)).toBe(false);
  });

  it("caching and reading degrade to no-op / null when unsupported", async () => {
    removeIndexedDb();
    const file = new File([new Uint8Array(10)], "x_R1.fastq.gz");
    expect(await cacheUploadFile(1, "k", file)).toBe(false);
    expect(await getCachedUploadFile(1, "k")).toBeNull();
  });
});

describe("uploadByteCache round-trip", () => {
  beforeEach(() => installFakeIndexedDb());

  it("caches a small file and recovers it as a File, then clears it", async () => {
    const file = new File([new Uint8Array(1024)], "small_R1.fastq.gz", {
      type: "application/gzip",
    });
    expect(await cacheUploadFile(7, "samples/7/a_R1", file)).toBe(true);

    const recovered = await getCachedUploadFile(7, "samples/7/a_R1");
    expect(recovered).not.toBeNull();
    expect(recovered?.name).toBe("small_R1.fastq.gz");
    expect(recovered?.size).toBe(1024);

    await clearCachedUploadFile(7, "samples/7/a_R1");
    expect(await getCachedUploadFile(7, "samples/7/a_R1")).toBeNull();
  });

  it("refuses to cache an oversized file (size gate)", async () => {
    const huge = { size: MAX_CACHEABLE_BYTES + 1, name: "huge", type: "" };
    expect(await cacheUploadFile(7, "big", huge as unknown as File)).toBe(
      false,
    );
    expect(await getCachedUploadFile(7, "big")).toBeNull();
  });

  it("clears every cached file for a project but leaves other projects", async () => {
    await cacheUploadFile(7, "a", new File([new Uint8Array(10)], "a"));
    await cacheUploadFile(7, "b", new File([new Uint8Array(10)], "b"));
    await cacheUploadFile(8, "c", new File([new Uint8Array(10)], "c"));

    await clearProjectByteCache(7);

    expect(await getCachedUploadFile(7, "a")).toBeNull();
    expect(await getCachedUploadFile(7, "b")).toBeNull();
    expect(await getCachedUploadFile(8, "c")).not.toBeNull();
  });
});
