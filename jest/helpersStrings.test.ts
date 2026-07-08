// #586 (epic #462) coverage: helpers/strings.ts holds a family of display
// formatters (comma grouping, humanize, line wrapping, SI prefixing, special-char
// scrubbing). Branch-rich and pure -- exercised across both arms.
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

describe("numberWithCommas", () => {
  it("groups thousands with commas", () => {
    expect(numberWithCommas(1234567)).toBe("1,234,567");
    expect(numberWithCommas(999)).toBe("999");
  });

  it("handles negative numbers", () => {
    expect(numberWithCommas(-12345)).toBe("-12,345");
  });

  it("returns nullish input unchanged", () => {
    expect(numberWithCommas(null)).toBeNull();
    expect(numberWithCommas(undefined)).toBeUndefined();
  });
});

describe("humanize", () => {
  it("splits on underscores and title-cases each word", () => {
    expect(humanize("taxon_tree")).toBe("Taxon Tree");
    expect(humanize("host")).toBe("Host");
  });
});

describe("splitIntoMultipleLines", () => {
  it("wraps words onto new lines once the max is exceeded", () => {
    expect(splitIntoMultipleLines("one two three four", 8)).toEqual([
      "one two",
      "three",
      "four",
    ]);
  });

  it("keeps a short string on a single line", () => {
    expect(splitIntoMultipleLines("short", 20)).toEqual(["short"]);
  });
});

describe("numberWithPlusOrMinus", () => {
  it("returns a comma-grouped plus-minus string for two numbers", () => {
    const result = numberWithPlusOrMinus(1234, 56);
    expect(result).toContain("1,234");
    expect(result).toContain("56");
  });

  it("returns null when either argument is not a number", () => {
    // @ts-expect-error intentionally passing a non-number
    expect(numberWithPlusOrMinus("x", 5)).toBeNull();
    // @ts-expect-error intentionally passing a non-number
    expect(numberWithPlusOrMinus(5, "y")).toBeNull();
  });
});

describe("formatSemanticVersion", () => {
  it("keeps only major.minor", () => {
    expect(formatSemanticVersion("3.10.2")).toBe("3.10");
  });

  it("returns undefined for a falsy version", () => {
    expect(formatSemanticVersion("")).toBeUndefined();
  });
});

describe("numberWithSiPrefix", () => {
  it("leaves sub-thousand values as plain strings", () => {
    expect(numberWithSiPrefix(500)).toBe("500");
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
  });
});

describe("special character helpers", () => {
  it("replaces disallowed characters with dashes", () => {
    expect(replaceSpecialCharacters("a/b*c")).toBe("a-b-c");
  });

  it("detects the presence of special characters", () => {
    expect(testForSpecialCharacters("clean_name-1")).toBe(false);
    expect(testForSpecialCharacters("bad$name")).toBe(true);
  });
});
