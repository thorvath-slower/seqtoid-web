// #586 (epic #462) coverage: objectUtil holds deep-diff, snake->camel key
// conversion, an array->lookup reducer, and two bidirectional maps that throw on
// duplicate values. Branchy (recursion + dup detection) and pure.
import {
  camelize,
  diff,
  reduceObjectArrayToLookupDict,
  TwoWayKeyListMap,
  TwoWayKeyStringMap,
} from "../app/assets/src/components/utils/objectUtil";

describe("diff", () => {
  it("returns only the keys whose values differ from the base", () => {
    const target = { b: 2, c: ["1", "2"], d: { baz: 1, bat: 2 }, e: 1 };
    const base = { a: 1, b: 2, c: ["2", "1"], d: { baz: 1, bat: 2 } };
    expect(diff(target, base)).toEqual({ c: ["1", "2"], e: 1 });
  });

  it("recurses into nested objects and returns nested differences", () => {
    const target = { d: { baz: 1, bat: 9 } };
    const base = { d: { baz: 1, bat: 2 } };
    expect(diff(target, base)).toEqual({ d: { bat: 9 } });
  });

  it("returns an empty object when target matches base", () => {
    expect(diff({ a: 1 }, { a: 1 })).toEqual({});
  });
});

describe("reduceObjectArrayToLookupDict", () => {
  it("keys the array of objects by the requested field", () => {
    const arr = [
      { id: "a", n: 1 },
      { id: "b", n: 2 },
    ];
    expect(reduceObjectArrayToLookupDict(arr, "id")).toEqual({
      a: { id: "a", n: 1 },
      b: { id: "b", n: 2 },
    });
  });

  it("returns an empty object for an empty array", () => {
    expect(reduceObjectArrayToLookupDict([], "id")).toEqual({});
  });
});

describe("camelize", () => {
  it("camelCases keys at every nesting level", () => {
    expect(camelize({ foo_bar: 1, nested_obj: { inner_key: 2 } })).toEqual({
      fooBar: 1,
      nestedObj: { innerKey: 2 },
    });
  });

  it("returns primitives unchanged", () => {
    expect(camelize(5)).toBe(5);
    expect(camelize("str")).toBe("str");
  });
});

describe("TwoWayKeyStringMap", () => {
  it("looks up in both directions", () => {
    const map = new TwoWayKeyStringMap({ a: "1", b: "2" });
    expect(map.get("a")).toBe("1");
    expect(map.revGet("2")).toBe("b");
  });

  it("throws when a value is duplicated", () => {
    expect(() => new TwoWayKeyStringMap({ a: "1", b: "1" })).toThrow(
      /Duplicate value/,
    );
  });
});

describe("TwoWayKeyListMap", () => {
  it("maps key to a value list and each value back to its key", () => {
    const map = new TwoWayKeyListMap({ a: ["1", "2"], b: ["3"] });
    expect(map.get("a")).toEqual(["1", "2"]);
    expect(map.revGet("2")).toBe("a");
    expect(map.revGet("3")).toBe("b");
  });

  it("throws when the same value appears in more than one list", () => {
    expect(() => new TwoWayKeyListMap({ a: ["1"], b: ["1"] })).toThrow(
      /Duplicate value/,
    );
  });
});
