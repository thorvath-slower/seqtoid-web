// CZID-462 (#586) coverage: app/assets/src/helpers/strings.ts
import {
  formatSemanticVersion,
  humanize,
  numberWithCommas,
  numberWithPercent,
  numberWithPlusOrMinus,
  numberWithSiPrefix,
  replaceSpecialCharacters,
  splitIntoMultipleLines,
  testForSpecialCharacters,
} from "../app/assets/src/helpers/strings";

describe("helpers/strings.ts", () => {
  describe("numberWithCommas", () => {
    it("returns nil input unchanged", () => {
      expect(numberWithCommas(null)).toBeNull();
      expect(numberWithCommas(undefined)).toBeUndefined();
    });
    it("inserts thousands separators", () => {
      expect(numberWithCommas(1234567)).toBe("1,234,567");
      expect(numberWithCommas(-12345)).toBe("-12,345");
      expect(numberWithCommas(100)).toBe("100");
    });
  });

  describe("humanize", () => {
    it("splits on underscores and title-cases", () => {
      expect(humanize("taxon_tree")).toBe("Taxon Tree");
      expect(humanize("sample")).toBe("Sample");
    });
  });

  describe("splitIntoMultipleLines", () => {
    it("wraps words at the max character boundary", () => {
      expect(splitIntoMultipleLines("one two three four", 8)).toEqual([
        "one two",
        "three",
        "four",
      ]);
    });
    it("keeps a single short string on one line", () => {
      expect(splitIntoMultipleLines("short", 20)).toEqual(["short"]);
    });
  });

  describe("numberWithPlusOrMinus", () => {
    it("returns null when either argument is not a number", () => {
      // @ts-expect-error deliberately passing a non-number
      expect(numberWithPlusOrMinus("x", 1)).toBeNull();
      // @ts-expect-error deliberately passing a non-number
      expect(numberWithPlusOrMinus(1, "y")).toBeNull();
    });
    it("formats rounded values with a plus/minus separator", () => {
      expect(numberWithPlusOrMinus(1234.6, 12.2)).toBe("1,235±12");
    });
  });

  describe("formatSemanticVersion", () => {
    it("keeps only major.minor", () => {
      expect(formatSemanticVersion("1.2.3")).toBe("1.2");
    });
    it("returns undefined for empty input", () => {
      expect(formatSemanticVersion("")).toBeUndefined();
    });
  });

  describe("numberWithSiPrefix", () => {
    it("keeps small numbers as-is", () => {
      expect(numberWithSiPrefix(999)).toBe("999");
    });
    it("uses K for thousands", () => {
      expect(numberWithSiPrefix(2000)).toBe("2K");
    });
    it("uses M for millions", () => {
      expect(numberWithSiPrefix(3000000)).toBe("3M");
    });
  });

  describe("numberWithPercent", () => {
    it("appends a percent sign", () => {
      expect(numberWithPercent(42)).toBe("42%");
      expect(numberWithPercent("50")).toBe("50%");
    });
  });

  describe("special character helpers", () => {
    it("replaces special characters with dashes", () => {
      expect(replaceSpecialCharacters("a!b@c")).toBe("a-b-c");
      expect(replaceSpecialCharacters("clean_name-1")).toBe("clean_name-1");
    });
    it("detects the presence of special characters", () => {
      expect(testForSpecialCharacters("has!bang")).toBe(true);
      expect(testForSpecialCharacters("clean name_1")).toBe(false);
    });
  });
});
