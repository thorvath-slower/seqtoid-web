// #586 (epic #462) coverage: typeUtils holds two TS guard helpers. isNotNullish
// is used in .filter() chains; checkExhaustive is the never-guard for switch
// exhaustiveness and must throw if ever reached at runtime.
import {
  checkExhaustive,
  isNotNullish,
} from "../app/assets/src/components/utils/typeUtils";

describe("isNotNullish", () => {
  it("returns false for null and undefined", () => {
    expect(isNotNullish(null)).toBe(false);
    expect(isNotNullish(undefined)).toBe(false);
  });

  it("returns true for falsy-but-defined values", () => {
    expect(isNotNullish(0)).toBe(true);
    expect(isNotNullish("")).toBe(true);
    expect(isNotNullish(false)).toBe(true);
  });

  it("returns true for objects and non-empty values", () => {
    expect(isNotNullish({})).toBe(true);
    expect(isNotNullish("x")).toBe(true);
  });

  it("filters null/undefined out of an array while narrowing type", () => {
    const arr = [1, null, 2, undefined, 3];
    expect(arr.filter(isNotNullish)).toEqual([1, 2, 3]);
  });
});

describe("checkExhaustive", () => {
  it("throws referencing the unexpected value", () => {
    // Cast through unknown because the signature only accepts never.
    expect(() => checkExhaustive("unexpected" as unknown as never)).toThrow(
      /unexpected/,
    );
  });
});
