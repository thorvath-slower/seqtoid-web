// CZID-462 (#586) coverage: app/assets/src/components/utils/format.ts
// Pure numeric/string formatters -- deterministic, no I/O.
import {
  formatFileSize,
  formatPercent,
  formatWithUnits,
  limitToRange,
} from "../app/assets/src/components/utils/format";

describe("format.ts", () => {
  describe("formatPercent", () => {
    it("multiplies by 100 and appends a percent sign with one decimal", () => {
      expect(formatPercent(0.5)).toBe("50.0%");
      expect(formatPercent(0.12345)).toBe("12.3%");
      expect(formatPercent(0)).toBe("0.0%");
      expect(formatPercent(1)).toBe("100.0%");
    });
  });

  describe("limitToRange", () => {
    it("returns the value when it is inside the range", () => {
      expect(limitToRange(5, 0, 10)).toBe(5);
    });
    it("clamps to the max when above", () => {
      expect(limitToRange(50, 0, 10)).toBe(10);
    });
    it("clamps to the min when below", () => {
      expect(limitToRange(-5, 0, 10)).toBe(0);
    });
  });

  describe("formatWithUnits", () => {
    it("keeps the base unit without decimals when below the factor", () => {
      expect(formatWithUnits(500, 1024, ["B", "kB", "MB"])).toBe("500 B");
    });
    it("scales up and applies the default single decimal", () => {
      expect(formatWithUnits(2048, 1024, ["B", "kB", "MB"])).toBe("2.0 kB");
    });
    it("respects an explicit decimals argument", () => {
      expect(formatWithUnits(2048, 1024, ["B", "kB", "MB"], 2)).toBe("2.00 kB");
    });
    it("stops scaling at the last available unit", () => {
      // 1024^3 with only two units available caps at kB.
      expect(formatWithUnits(1024 * 1024, 1024, ["B", "kB"])).toBe("1024.0 kB");
    });
    it("handles negative numbers via the absolute-value check", () => {
      expect(formatWithUnits(-2048, 1024, ["B", "kB", "MB"])).toBe("-2.0 kB");
    });
  });

  describe("formatFileSize", () => {
    it("formats bytes using the default 1024 factor and unit list", () => {
      expect(formatFileSize(1234)).toBe("1.2 kB");
      expect(formatFileSize(0)).toBe("0 B");
    });
    it("scales into megabytes", () => {
      expect(formatFileSize(5 * 1024 * 1024)).toBe("5.0 MB");
    });
  });
});
