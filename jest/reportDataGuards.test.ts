// Regression coverage for #386: report/data views used to throw unhandled
// TypeErrors ("forEach/map is not a function", "'in' on null") when a GraphQL /
// report_v2 response came back null or with an unexpected shape. These tests pin
// the null/odd-response paths of the pure helpers used by
// SampleView#processRawSampleReportData so a degenerate response degrades
// gracefully instead of crashing the report view.
import {
  adjustMetricPrecision,
  setDisplayName,
} from "../app/assets/src/components/views/SampleView/utils/filters";
import { getGeneraPathogenCounts } from "../app/assets/src/helpers/taxon";

describe("getGeneraPathogenCounts (null-response guard)", () => {
  it("returns {} for a null species-counts map instead of throwing", () => {
    // Object.values(null) previously threw "forEach on undefined".
    expect(() =>
      getGeneraPathogenCounts(null as $TSFixMe),
    ).not.toThrow();
    expect(getGeneraPathogenCounts(null as $TSFixMe)).toEqual({});
  });

  it("returns {} for an undefined species-counts map", () => {
    expect(getGeneraPathogenCounts(undefined as $TSFixMe)).toEqual({});
  });

  it("ignores species entries that are missing a pathogenFlag", () => {
    const counts = {
      "1": { genus_tax_id: "10", pathogenFlag: "known" },
      "2": { genus_tax_id: "10" } as $TSFixMe, // no pathogenFlag
    };
    expect(getGeneraPathogenCounts(counts)).toEqual({ "10": { known: 1 } });
  });
});

describe("adjustMetricPrecision (null/odd-shape guard)", () => {
  it("returns the value unchanged (no throw) when species is null", () => {
    // Object.entries(null) previously threw; `key in null` previously threw
    // "right-hand side of 'in' should be an object, got null".
    expect(() => adjustMetricPrecision(null)).not.toThrow();
    expect(adjustMetricPrecision(null)).toBeNull();
  });

  it("returns the value unchanged when species is undefined", () => {
    expect(() => adjustMetricPrecision(undefined)).not.toThrow();
    expect(adjustMetricPrecision(undefined)).toBeUndefined();
  });

  it("tolerates a null nt/nr sub-object without throwing", () => {
    const species = { z_score: 1.234, nt: null, nr: undefined };
    expect(() => adjustMetricPrecision(species)).not.toThrow();
    const result = adjustMetricPrecision(species);
    expect(result.z_score).toBe(1.2);
  });

  it("rounds nested nt metrics when present", () => {
    const species = { nt: { rpm: 1.239 } };
    const result = adjustMetricPrecision(species);
    expect(result.nt.rpm).toBe(1.2);
  });
});

describe("setDisplayName (null/odd-shape guard)", () => {
  it("does not throw when reportData is undefined", () => {
    expect(() =>
      setDisplayName({ reportData: undefined as $TSFixMe, nameType: "Scientific name" }),
    ).not.toThrow();
  });

  it("does not throw when a genus has no species array", () => {
    const reportData = [
      { name: "Genus A", common_name: "a", species: undefined } as $TSFixMe,
    ];
    expect(() =>
      setDisplayName({ reportData, nameType: "Scientific name" }),
    ).not.toThrow();
    expect(reportData[0].displayName).toBe("Genus A");
  });

  it("sets scientific display names for genus and species", () => {
    const reportData = [
      {
        name: "Genus A",
        common_name: "genus a",
        species: [{ name: "Species A", common_name: "species a" }],
      } as $TSFixMe,
    ];
    setDisplayName({ reportData, nameType: "Scientific name" });
    expect(reportData[0].displayName).toBe("Genus A");
    expect(reportData[0].species[0].displayName).toBe("Species A");
  });
});
