// #586 (epic #462) coverage: helpers/storage.ts wraps Storage get/set in try/catch
// to survive corrupt state. Exercises the happy path plus both catch arms via a
// throwing/garbage-returning fake store.
import { loadState, setState } from "../app/assets/src/helpers/storage";

const makeStore = (overrides: Partial<Storage> = {}): Storage =>
  ({
    getItem: jest.fn(),
    setItem: jest.fn(),
    removeItem: jest.fn(),
    clear: jest.fn(),
    key: jest.fn(),
    length: 0,
    ...overrides,
  } as unknown as Storage);

describe("loadState", () => {
  it("parses and returns stored JSON", () => {
    const store = makeStore({
      getItem: jest.fn().mockReturnValue(JSON.stringify({ a: 1 })),
    });
    expect(loadState(store, "key")).toEqual({ a: 1 });
  });

  it("returns an empty object when the stored value is null", () => {
    const store = makeStore({ getItem: jest.fn().mockReturnValue(null) });
    expect(loadState(store, "key")).toEqual({});
  });

  it("returns an empty object and warns on invalid JSON", () => {
    const warn = jest
      .spyOn(console, "warn")
      .mockImplementation(() => undefined);
    const store = makeStore({
      getItem: jest.fn().mockReturnValue("{not json"),
    });
    expect(loadState(store, "key")).toEqual({});
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });
});

describe("setState", () => {
  it("serializes and stores the state", () => {
    const setItem = jest.fn();
    const store = makeStore({ setItem });
    setState(store, "key", { b: 2 });
    expect(setItem).toHaveBeenCalledWith("key", JSON.stringify({ b: 2 }));
  });

  it("swallows and warns when setItem throws", () => {
    const warn = jest
      .spyOn(console, "warn")
      .mockImplementation(() => undefined);
    const store = makeStore({
      setItem: jest.fn(() => {
        throw new Error("quota");
      }),
    });
    expect(() => setState(store, "key", { b: 2 })).not.toThrow();
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });
});
