// CZID-462 (#498) coverage gap: convertStringAndRoundToHundredths formats numeric
// metrics shown on report views. Pure + deterministic.
import { convertStringAndRoundToHundredths } from "../app/assets/src/components/utils/numberUtil";

describe("convertStringAndRoundToHundredths", () => {
  it("rounds to two decimal places", () => {
    expect(convertStringAndRoundToHundredths("1.239")).toBe(1.24);
    expect(convertStringAndRoundToHundredths("1.234")).toBe(1.23);
  });

  it("leaves values already at hundredths unchanged", () => {
    expect(convertStringAndRoundToHundredths("3.14")).toBe(3.14);
  });

  it("handles integer strings", () => {
    expect(convertStringAndRoundToHundredths("42")).toBe(42);
  });

  it("handles negative values", () => {
    expect(convertStringAndRoundToHundredths("-1.005")).toBe(-1);
  });

  it("parses leading-numeric strings (parseFloat semantics)", () => {
    expect(convertStringAndRoundToHundredths("2.5abc")).toBe(2.5);
  });

  it("returns NaN for non-numeric input", () => {
    expect(convertStringAndRoundToHundredths("abc")).toBeNaN();
  });
});
