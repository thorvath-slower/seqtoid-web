// CZID-462 (#586) coverage: app/assets/src/components/utils/ThresholdMap.ts
import ThresholdMap, {
  ThresholdConditions,
} from "../app/assets/src/components/utils/ThresholdMap";

const makeThreshold = (
  over: Partial<ThresholdConditions> = {},
): ThresholdConditions => ({
  metric: "nt_zscore",
  operator: ">=",
  value: "1",
  metricDisplay: "NT Z Score",
  ...over,
});

describe("ThresholdMap", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  describe("isThresholdValid", () => {
    it("is true for a fully-specified numeric threshold", () => {
      expect(ThresholdMap.isThresholdValid(makeThreshold())).toBe(true);
    });
    it("is false when the value is not numeric", () => {
      expect(
        ThresholdMap.isThresholdValid(makeThreshold({ value: "abc" })),
      ).toBe(false);
    });
    it("is false when the value is an empty string", () => {
      expect(ThresholdMap.isThresholdValid(makeThreshold({ value: "" }))).toBe(
        false,
      );
    });
    it("is false when a required field is missing", () => {
      // metric undefined -> the outer guard short-circuits to false
      expect(
        ThresholdMap.isThresholdValid({
          operator: ">=",
          value: "1",
        } as ThresholdConditions),
      ).toBe(false);
    });
  });

  describe("localStorage persistence", () => {
    it("returns an empty array when nothing is saved", () => {
      expect(ThresholdMap.getSavedThresholdFilters()).toEqual([]);
    });
    it("saves only valid thresholds and reads them back", () => {
      const valid = makeThreshold();
      const invalid = makeThreshold({ value: "" });
      ThresholdMap.saveThresholdFilters([valid, invalid]);
      expect(ThresholdMap.getSavedThresholdFilters()).toEqual([valid]);
    });
  });

  describe("taxonPassThresholdFilter", () => {
    const taxon = { nt: { zscore: 5 } };

    it("returns false for an empty taxon object", () => {
      expect(ThresholdMap.taxonPassThresholdFilter({}, [makeThreshold()])).toBe(
        false,
      );
    });
    it("passes when a >= rule is satisfied", () => {
      expect(
        ThresholdMap.taxonPassThresholdFilter(taxon, [
          makeThreshold({ value: "3" }),
        ]),
      ).toBe(true);
    });
    it("fails when a >= rule is not satisfied", () => {
      expect(
        ThresholdMap.taxonPassThresholdFilter(taxon, [
          makeThreshold({ value: "10" }),
        ]),
      ).toBe(false);
    });
    it("handles the <= operator", () => {
      expect(
        ThresholdMap.taxonPassThresholdFilter(taxon, [
          makeThreshold({ operator: "<=", value: "10" }),
        ]),
      ).toBe(true);
      expect(
        ThresholdMap.taxonPassThresholdFilter(taxon, [
          makeThreshold({ operator: "<=", value: "1" }),
        ]),
      ).toBe(false);
    });
    it("ignores invalid rules", () => {
      expect(
        ThresholdMap.taxonPassThresholdFilter(taxon, [
          makeThreshold({ value: "" }),
        ]),
      ).toBe(true);
    });
  });
});
