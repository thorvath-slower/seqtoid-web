// CZID-462 (#586) coverage: app/assets/src/components/utils/objectUtil.ts
import {
  camelize,
  diff,
  reduceObjectArrayToLookupDict,
  TwoWayKeyListMap,
  TwoWayKeyStringMap,
} from "../app/assets/src/components/utils/objectUtil";

describe("objectUtil.ts", () => {
  describe("diff", () => {
    it("returns only the changed/added keys, recursing into nested objects", () => {
      const obj1 = { b: 2, c: ["2", "1"], d: { baz: 1, bat: 2 }, e: 1 };
      const obj2 = { a: 1, b: 2, c: ["1", "2"], d: { baz: 1, bat: 2 } };
      // diff surfaces the target's array values (element-wise) for changed arrays.
      expect(diff(obj1, obj2)).toEqual({ c: ["2", "1"], e: 1 });
    });
    it("returns an empty object when there are no differences", () => {
      expect(diff({ a: 1 }, { a: 1 })).toEqual({});
    });
  });

  describe("reduceObjectArrayToLookupDict", () => {
    it("keys an array of objects by the chosen field", () => {
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
    it("camelCases keys of a nested object", () => {
      expect(camelize({ foo_bar: 1, nested_obj: { inner_key: 2 } })).toEqual({
        fooBar: 1,
        nestedObj: { innerKey: 2 },
      });
    });
    it("camelCases array elements (arrays are treated as objects, keyed by index)", () => {
      expect(camelize([{ foo_bar: 1 }])).toEqual({ "0": { fooBar: 1 } });
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
    it("throws on duplicate values", () => {
      expect(() => new TwoWayKeyStringMap({ a: "1", b: "1" })).toThrow(
        /Duplicate value, 1, in TwoWayMap/,
      );
    });
  });

  describe("TwoWayKeyListMap", () => {
    it("maps a key to a value list and each value back to its key", () => {
      const map = new TwoWayKeyListMap({ a: ["1", "2"], b: ["3"] });
      expect(map.get("a")).toEqual(["1", "2"]);
      expect(map.revGet("1")).toBe("a");
      expect(map.revGet("3")).toBe("b");
    });
    it("throws when a value appears in more than one list", () => {
      expect(() => new TwoWayKeyListMap({ a: ["1"], b: ["1"] })).toThrow(
        /Duplicate value, 1, in TwoWayKeyListMap/,
      );
    });
  });
});
