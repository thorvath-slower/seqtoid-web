// CZID-462 (#586) coverage: app/assets/src/components/utils/taxon.ts
import {
  getCategoryAdjective,
  getTaxonMetric,
} from "../app/assets/src/components/utils/taxon";

describe("utils/taxon.ts", () => {
  describe("getTaxonMetric", () => {
    it("reads contig metrics from summaryContigCounts", () => {
      const taxon = {
        summaryContigCounts: { nt: { contigs: 7, contigreads: 42 } },
      };
      expect(getTaxonMetric(taxon, "nt", "contigs")).toBe(7);
      expect(getTaxonMetric(taxon, "nt", "contigreads")).toBe(42);
    });
    it("defaults contig metrics to 0 when the path is missing", () => {
      expect(getTaxonMetric({}, "nt", "contigs")).toBe(0);
    });
    it("reads non-contig metrics directly off the type object", () => {
      const taxon = { nr: { rpm: 3.14 } };
      expect(getTaxonMetric(taxon, "nr", "rpm")).toBe(3.14);
    });
  });

  describe("getCategoryAdjective", () => {
    it.each([
      ["Bacteria", "bacterial"],
      ["Archaea", "archaeal"],
      ["Eukaryota", "eukaryotic"],
      ["Viruses", "viral"],
      ["Viroids", "viroidal"],
      ["Uncategorized", "uncategorized"],
    ])("maps %s to %s", (input, expected) => {
      expect(getCategoryAdjective(input)).toBe(expected);
    });
    it("falls back to the lowercased category for unknown values", () => {
      expect(getCategoryAdjective("Protozoa")).toBe("protozoa");
    });
  });
});
