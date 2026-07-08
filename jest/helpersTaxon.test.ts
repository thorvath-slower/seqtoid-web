// #586 (epic #462) coverage: helpers/taxon.ts picks a display name (scientific vs
// capitalized common) and aggregates genus-level pathogen counts from species
// counts, guarding against a nullish counts map (#386). Branch-rich and pure.
import {
  getGeneraPathogenCounts,
  getTaxonName,
} from "../app/assets/src/helpers/taxon";

describe("getTaxonName", () => {
  it("returns the scientific name when nameType is not common name", () => {
    expect(getTaxonName("Homo sapiens", "human", "Scientific Name")).toBe(
      "Homo sapiens",
    );
  });

  it("returns the capitalized common name when requested and available", () => {
    expect(getTaxonName("Homo sapiens", "human", "Common Name")).toBe("Human");
  });

  it("falls back to scientific name when common name is empty/whitespace", () => {
    expect(getTaxonName("Homo sapiens", "   ", "Common Name")).toBe(
      "Homo sapiens",
    );
    expect(getTaxonName("Homo sapiens", "", "common name")).toBe(
      "Homo sapiens",
    );
  });
});

describe("getGeneraPathogenCounts", () => {
  it("returns an empty object for null/undefined counts (#386 guard)", () => {
    expect(getGeneraPathogenCounts(null)).toEqual({});
    expect(getGeneraPathogenCounts(undefined)).toEqual({});
  });

  it("tallies pathogen flags per genus, skipping unflagged species", () => {
    const speciesCounts = {
      s1: { pathogenFlag: "knownPathogen", genus_tax_id: "10" },
      s2: { pathogenFlag: "knownPathogen", genus_tax_id: "10" },
      s3: { pathogenFlag: "", genus_tax_id: "20" },
    } as any;
    expect(getGeneraPathogenCounts(speciesCounts)).toEqual({
      "10": { knownPathogen: 2 },
    });
  });
});
