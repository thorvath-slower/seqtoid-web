// CZID-462 (#498) coverage gap: ArrayUtils.findClosestNeighbors is a binary search
// used to snap values onto sorted axis ticks (heatmap / histogram rendering). Binary
// search + boundary handling is exactly the kind of edge-case-rich pure code worth
// pinning. Pure + deterministic.
import ArrayUtils from "../app/assets/src/components/utils/ArrayUtils";

describe("ArrayUtils.equal", () => {
  it("returns true for the same reference", () => {
    const a = [1, 2, 3];
    expect(ArrayUtils.equal(a, a)).toBe(true);
  });

  it("returns true for shallow-equal arrays", () => {
    expect(ArrayUtils.equal([1, 2, 3], [1, 2, 3])).toBe(true);
  });

  it("returns false for different lengths", () => {
    expect(ArrayUtils.equal([1, 2], [1, 2, 3])).toBe(false);
  });

  it("returns false when an element differs", () => {
    expect(ArrayUtils.equal([1, 2, 3], [1, 9, 3])).toBe(false);
  });

  it("compares only by reference for objects (one-level)", () => {
    const obj = {};
    expect(ArrayUtils.equal([obj], [obj])).toBe(true);
    expect(ArrayUtils.equal([{}], [{}])).toBe(false);
  });

  it("returns false when either argument is not an array", () => {
    // @ts-expect-error intentionally passing a non-array
    expect(ArrayUtils.equal([1], "1")).toBe(false);
  });
});

describe("ArrayUtils.findClosestNeighbors", () => {
  it("returns [] for an empty array", () => {
    expect(ArrayUtils.findClosestNeighbors([], 5)).toEqual([]);
  });

  it("returns the single element twice for a one-element array", () => {
    expect(ArrayUtils.findClosestNeighbors([7], 5)).toEqual([7, 7]);
  });

  it("returns the bracketing pair for a value between elements", () => {
    expect(ArrayUtils.findClosestNeighbors([1, 3, 5, 7], 4)).toEqual([3, 5]);
  });

  it("returns the bracketing pair when the value equals an element", () => {
    // <= sends equal values to `low`, so an exact hit brackets to the next up.
    expect(ArrayUtils.findClosestNeighbors([1, 3, 5, 7], 5)).toEqual([5, 7]);
  });

  it("returns a single element when the value is below the range", () => {
    expect(ArrayUtils.findClosestNeighbors([10, 20, 30], 5)).toEqual([10]);
  });

  it("returns a single element when the value is above the range", () => {
    expect(ArrayUtils.findClosestNeighbors([10, 20, 30], 99)).toEqual([30]);
  });
});

describe("ArrayUtils.caseInsensitiveIncludes", () => {
  it("matches regardless of case", () => {
    expect(ArrayUtils.caseInsensitiveIncludes(["Apple", "Banana"], "APPLE")).toBe(
      true,
    );
  });

  it("returns false when absent", () => {
    expect(ArrayUtils.caseInsensitiveIncludes(["Apple"], "pear")).toBe(false);
  });

  it("treats a null/undefined filter as an empty string", () => {
    // @ts-expect-error intentionally passing null for the filter
    expect(ArrayUtils.caseInsensitiveIncludes(["a", ""], null)).toBe(true);
  });
});
