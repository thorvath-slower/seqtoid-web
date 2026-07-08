// #586 (epic #462) coverage: format.ts holds pure numeric/byte formatters used
// across report and upload views. formatWithUnits carries a scaling loop with
// branch arms (zero-unit vs scaled, decimals default) worth pinning. Pure + deterministic.
import {
  formatFileSize,
  formatPercent,
  formatWithUnits,
  limitToRange,
} from "../app/assets/src/components/utils/format";

describe("formatPercent", () => {
  it("multiplies by 100 and fixes to one decimal with a percent sign", () => {
    expect(formatPercent(0.5)).toBe("50.0%");
    expect(formatPercent(0.123)).toBe("12.3%");
  });

  it("handles zero", () => {
    expect(formatPercent(0)).toBe("0.0%");
  });
});

describe("limitToRange", () => {
  it("returns the value when already within range", () => {
    expect(limitToRange(5, 0, 10)).toBe(5);
  });

  it("clamps to the min when below range", () => {
    expect(limitToRange(-3, 0, 10)).toBe(0);
  });

  it("clamps to the max when above range", () => {
    expect(limitToRange(99, 0, 10)).toBe(10);
  });
});

describe("formatFileSize", () => {
  it("leaves sub-unit values without decimals", () => {
    expect(formatFileSize(512)).toBe("512 B");
  });

  it("scales 1234 bytes into kB with one decimal", () => {
    expect(formatFileSize(1234)).toBe("1.2 kB");
  });

  it("scales into MB", () => {
    expect(formatFileSize(1024 * 1024 * 3)).toBe("3.0 MB");
  });

  it("honors a custom decimals argument", () => {
    expect(formatFileSize(1234, undefined, 2)).toBe("1.21 kB");
  });
});

describe("formatWithUnits", () => {
  it("returns the raw number (no decimals) when no scaling is needed", () => {
    expect(formatWithUnits(3, 1000, ["", "K", "M"])).toBe("3 ");
  });

  it("scales up while above the unit factor and stops at the last unit", () => {
    // 5,000,000 / 1000 / 1000 = 5 M, but should not exceed the final unit.
    expect(formatWithUnits(5000000, 1000, ["", "K", "M"])).toBe("5.0 M");
  });

  it("stops scaling at the last available unit even when still large", () => {
    // Only two units: cannot advance past index 1.
    expect(formatWithUnits(5000000, 1000, ["", "K"])).toBe("5000.0 K");
  });

  it("handles negative magnitudes via Math.abs in the loop condition", () => {
    expect(formatWithUnits(-2000, 1000, ["", "K"])).toBe("-2.0 K");
  });
});
