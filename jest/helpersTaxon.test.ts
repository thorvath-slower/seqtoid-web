// CZID-462 (#586) coverage: app/assets/src/helpers/taxon.ts
import {
  getGeneraPathogenCounts,
  getTaxonName,
} from "../app/assets/src/helpers/taxon";

describe("helpers/taxon.ts", () => {
  describe("getTaxonName", () => {
    it("returns the scientific name when nameType is not 'common name'", () => {
      expect(getTaxonName("Escherichia coli", "E. coli", "Scientific")).toBe(
        "Escherichia coli",
      );
    });
    it("returns the capitalized common name when requested and available", () => {
      expect(getTaxonName("Escherichia coli", "e. coli", "Common Name")).toBe(
        "E. coli",
      );
    });
    it("falls back to scientific name when common name is blank", () => {
      expect(getTaxonName("Escherichia coli", "   ", "Common Name")).toBe(
        "Escherichia coli",
      );
      expect(getTaxonName("Escherichia coli", "", "common name")).toBe(
        "Escherichia coli",
      );
    });
  });

  describe("getGeneraPathogenCounts", () => {
    it("returns an empty object for null/undefined input", () => {
      expect(getGeneraPathogenCounts(null)).toEqual({});
      expect(getGeneraPathogenCounts(undefined)).toEqual({});
    });
    it("tallies pathogen flags per genus tax id", () => {
      const speciesCounts = {
        s1: { pathogenFlag: "knownPathogen", genus_tax_id: "10" },
        s2: { pathogenFlag: "knownPathogen", genus_tax_id: "10" },
        s3: { pathogenFlag: "lcrp", genus_tax_id: "20" },
      };
      expect(getGeneraPathogenCounts(speciesCounts)).toEqual({
        "10": { knownPathogen: 2 },
        "20": { lcrp: 1 },
      });
    });
    it("skips species without a pathogen flag", () => {
      const speciesCounts = {
        s1: { pathogenFlag: "", genus_tax_id: "10" },
      } as any;
      expect(getGeneraPathogenCounts(speciesCounts)).toEqual({});
    });
  });
});
