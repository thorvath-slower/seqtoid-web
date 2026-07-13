// CZID-462 (#586) coverage: app/assets/src/components/utils/typeUtils.ts
import {
  checkExhaustive,
  isNotNullish,
} from "../app/assets/src/components/utils/typeUtils";

describe("typeUtils.ts", () => {
  describe("isNotNullish", () => {
    it("returns true for non-nullish values including falsy ones", () => {
      expect(isNotNullish(0)).toBe(true);
      expect(isNotNullish("")).toBe(true);
      expect(isNotNullish(false)).toBe(true);
      expect(isNotNullish({})).toBe(true);
    });
    it("returns false for null and undefined", () => {
      expect(isNotNullish(null)).toBe(false);
      expect(isNotNullish(undefined)).toBe(false);
    });
    it("works as an Array.filter type guard", () => {
      const filtered = [1, null, 2, undefined, 3].filter(isNotNullish);
      expect(filtered).toEqual([1, 2, 3]);
    });
  });

  describe("checkExhaustive", () => {
    it("always throws, referencing the unexpected value", () => {
      expect(() => checkExhaustive("unexpected" as never)).toThrow(
        /Exhaustive switch check should never read here for value unexpected/,
      );
    });
  });
});
