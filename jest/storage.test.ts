// CZID-462 (#586) coverage: app/assets/src/helpers/storage.ts
import { loadState, setState } from "../app/assets/src/helpers/storage";

const makeStore = (): Storage => {
  const backing: Record<string, string> = {};
  return {
    getItem: (k: string) => (k in backing ? backing[k] : null),
    setItem: (k: string, v: string) => {
      backing[k] = v;
    },
    removeItem: (k: string) => {
      delete backing[k];
    },
    clear: () => {
      for (const k of Object.keys(backing)) delete backing[k];
    },
    key: () => null,
    length: 0,
  } as unknown as Storage;
};

describe("helpers/storage.ts", () => {
  let warnSpy: jest.SpyInstance;
  beforeEach(() => {
    warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
  });
  afterEach(() => {
    warnSpy.mockRestore();
  });

  describe("loadState", () => {
    it("parses previously stored JSON", () => {
      const store = makeStore();
      store.setItem("k", JSON.stringify({ a: 1 }));
      expect(loadState(store, "k")).toEqual({ a: 1 });
    });
    it("returns an empty object when the key is absent", () => {
      expect(loadState(makeStore(), "missing")).toEqual({});
    });
    it("returns an empty object and warns on malformed JSON", () => {
      const store = makeStore();
      store.setItem("bad", "{not json");
      expect(loadState(store, "bad")).toEqual({});
      expect(warnSpy).toHaveBeenCalled();
    });
  });

  describe("setState", () => {
    it("serializes state into the store", () => {
      const store = makeStore();
      setState(store, "k", { b: 2 });
      expect(store.getItem("k")).toBe(JSON.stringify({ b: 2 }));
    });
    it("warns when the store throws", () => {
      const throwing = {
        setItem: () => {
          throw new Error("quota");
        },
      } as unknown as Storage;
      expect(() => setState(throwing, "k", {})).not.toThrow();
      expect(warnSpy).toHaveBeenCalled();
    });
  });
});
