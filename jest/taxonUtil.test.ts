// #586 (epic #462) coverage: utils/taxon.ts pulls per-taxon metric values (with a
// contigs special-case + zero fallback) and maps category names to adjectives via
// a switch. Both are pure and branch-rich.
import {
  getCategoryAdjective,
  getTaxonMetric,
} from "../app/assets/src/components/utils/taxon";

describe("getTaxonMetric", () => {
  it("reads nested summaryContigCounts for the contigs metric", () => {
    const taxon = { summaryContigCounts: { nt: { contigs: 4 } } };
    expect(getTaxonMetric(taxon, "nt", "contigs")).toBe(4);
  });

  it("reads nested summaryContigCounts for the contigreads metric", () => {
    const taxon = { summaryContigCounts: { nr: { contigreads: 12 } } };
    expect(getTaxonMetric(taxon, "nr", "contigreads")).toBe(12);
  });

  it("falls back to 0 when the nested contig count is missing", () => {
    expect(getTaxonMetric({}, "nt", "contigs")).toBe(0);
  });

  it("reads a plain metric directly off the count-type object", () => {
    const taxon = { nt: { rpm: 99 } };
    expect(getTaxonMetric(taxon, "nt", "rpm")).toBe(99);
  });
});

describe("getCategoryAdjective", () => {
  it("maps known categories case-insensitively", () => {
    expect(getCategoryAdjective("Bacteria")).toBe("bacterial");
    expect(getCategoryAdjective("ARCHAEA")).toBe("archaeal");
    expect(getCategoryAdjective("eukaryota")).toBe("eukaryotic");
    expect(getCategoryAdjective("Viruses")).toBe("viral");
    expect(getCategoryAdjective("viroids")).toBe("viroidal");
    expect(getCategoryAdjective("Uncategorized")).toBe("uncategorized");
  });

  it("falls back to the lowercased category for unknown values", () => {
    expect(getCategoryAdjective("Fungi")).toBe("fungi");
  });
});
