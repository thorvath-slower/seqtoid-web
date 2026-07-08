// #586 (epic #462) coverage: ThresholdMap validates threshold rules, persists them
// to localStorage, and decides whether a taxon passes a set of >=/<= rules. The
// pass-filter carries operator branches and an early-exit on empty taxa. Uses jsdom
// localStorage; pure otherwise.
import ThresholdMap from "../app/assets/src/components/utils/ThresholdMap";

const validRule = {
  metric: "nt_rpm",
  operator: ">=" as const,
  value: "10",
  metricDisplay: "rPM",
};

describe("ThresholdMap.isThresholdValid", () => {
  it("accepts a complete numeric threshold", () => {
    expect(ThresholdMap.isThresholdValid(validRule)).toBe(true);
  });

  it("rejects a threshold with a non-numeric value", () => {
    expect(ThresholdMap.isThresholdValid({ ...validRule, value: "abc" })).toBe(
      false,
    );
  });

  it("rejects a threshold missing the metric", () => {
    expect(ThresholdMap.isThresholdValid({ ...validRule, metric: "" })).toBe(
      false,
    );
  });

  it("rejects a threshold with an empty value", () => {
    expect(ThresholdMap.isThresholdValid({ ...validRule, value: "" })).toBe(
      false,
    );
  });
});

describe("ThresholdMap localStorage persistence", () => {
  beforeEach(() => window.localStorage.clear());

  it("returns an empty array when nothing is saved", () => {
    expect(ThresholdMap.getSavedThresholdFilters()).toEqual([]);
  });

  it("saves only valid thresholds and reads them back", () => {
    const invalid = { ...validRule, value: "" };
    ThresholdMap.saveThresholdFilters([validRule, invalid]);
    expect(ThresholdMap.getSavedThresholdFilters()).toEqual([validRule]);
  });
});

describe("ThresholdMap.taxonPassThresholdFilter", () => {
  it("returns false for an empty taxon", () => {
    expect(ThresholdMap.taxonPassThresholdFilter({}, [validRule])).toBe(false);
  });

  it("passes when a >= rule is satisfied", () => {
    const taxon = { nt: { rpm: 50 } };
    expect(ThresholdMap.taxonPassThresholdFilter(taxon, [validRule])).toBe(
      true,
    );
  });

  it("fails when a >= rule is not satisfied", () => {
    const taxon = { nt: { rpm: 5 } };
    expect(ThresholdMap.taxonPassThresholdFilter(taxon, [validRule])).toBe(
      false,
    );
  });

  it("fails when a <= rule is exceeded", () => {
    const taxon = { nt: { rpm: 50 } };
    const rule = { ...validRule, operator: "<=" as const };
    expect(ThresholdMap.taxonPassThresholdFilter(taxon, [rule])).toBe(false);
  });

  it("passes when a <= rule is satisfied", () => {
    const taxon = { nt: { rpm: 5 } };
    const rule = { ...validRule, operator: "<=" as const };
    expect(ThresholdMap.taxonPassThresholdFilter(taxon, [rule])).toBe(true);
  });

  it("ignores invalid rules and still passes", () => {
    const taxon = { nt: { rpm: 5 } };
    const invalid = { ...validRule, value: "" };
    expect(ThresholdMap.taxonPassThresholdFilter(taxon, [invalid])).toBe(true);
  });
});
