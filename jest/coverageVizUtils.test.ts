// CZID-586 (#586) frontend coverage: CoverageVizBottomSidebar/utils.ts is a
// bundle of pure data-shaping helpers (tooltip builders, hit-group selectors,
// viz-data generators, accession aggregation). These are exercised on every
// mouse move in the coverage viz, and the tooltip builder in particular has a
// distinct arm per hit-group composition -- cover them all.
import {
  generateContigReadVizData,
  generateCoverageVizData,
  getCombinedAccessionDataForSpecies,
  getCoverageVizParams,
  getGenomeVizTooltipData,
  getHistogramTooltipData,
  getSortedAccessionSummaries,
  selectContigsFromHitGroups,
  selectReadsFromHitGroups,
} from "~/components/common/CoverageVizBottomSidebar/utils";

// coverage tuple: [binIndex, avgDepth, breadth, numContigs, numReads]
const accessionData = {
  coverage: [
    [0, 12, 0.5, 2, 3],
    [1, 4, 0.25, 0, 1],
  ],
  coverage_bin_size: 100,
  // hit_groups tuple:
  // [numContigs, numReads, contigR, start, end, alignLen, percentId, mismatches, gaps, binIndex]
  hit_groups: [
    [2, 3, 7, 10, 400, 380, 0.9, 5, 1, 0],
    [0, 1, 0, 50, 60, 10, 0.8, 0, 0, 1],
  ],
} as any;

describe("getHistogramTooltipData", () => {
  it("builds the coverage tooltip rows with a computed base-pair range", () => {
    const [section] = getHistogramTooltipData(accessionData, 0);
    expect(section.name).toBe("Coverage");
    const rows = Object.fromEntries(section.data as [string, string][]);
    // Source joins the range with an en-dash; use the escape so the test
    // source stays pure ASCII.
    expect(rows["Base Pair Range"]).toBe("0\u2013100");
    expect(rows["Coverage Depth"]).toBe("12x");
    expect(rows["Overlapping Contigs"]).toBe("2");
    expect(rows["Overlapping Loose Reads"]).toBe("3");
  });
});

describe("getGenomeVizTooltipData covers each hit-group composition", () => {
  const build = (hitObj: number[]) =>
    getGenomeVizTooltipData([hitObj] as any, 0)[0];

  it("aggregated contigs AND reads", () => {
    const s = build([2, 3, 7, 10, 400, 380, 0.9, 5, 1, 0]);
    expect(s.name).toBe("Aggregated NT Contigs and NT Reads");
  });
  it("aggregated loose reads (numReads > 1, no contigs)", () => {
    const s = build([0, 4, 0, 10, 20, 10, 0.9, 0, 0, 0]);
    expect(s.name).toBe("Aggregated Loose NT Reads");
  });
  it("a single loose read", () => {
    const s = build([0, 1, 0, 10, 20, 10, 0.9, 0, 0, 0]);
    expect(s.name).toBe("Loose NT Read");
  });
  it("aggregated contigs (numContigs > 1, no reads)", () => {
    const s = build([3, 0, 7, 10, 400, 380, 0.9, 5, 1, 0]);
    expect(s.name).toBe("Aggregated Contigs");
  });
  it("a single NT contig", () => {
    const s = build([1, 0, 7, 10, 400, 380, 0.9, 5, 1, 0]);
    expect(s.name).toBe("NT Contig");
  });
  it("uses the 'Avg.' prefix only when there are multiple hits", () => {
    const multi = build([2, 3, 7, 10, 400, 380, 0.9, 5, 1, 0]);
    const single = build([1, 0, 7, 10, 400, 380, 0.9, 5, 1, 0]);
    const multiKeys = (multi.data as [string, unknown][]).map(d => d[0]);
    const singleKeys = (single.data as [string, unknown][]).map(d => d[0]);
    expect(multiKeys).toContain("Avg. Alignment Length");
    expect(singleKeys).toContain("Alignment Length");
  });
});

describe("hit-group selectors", () => {
  it("selectContigsFromHitGroups keeps only groups with contigs", () => {
    expect(selectContigsFromHitGroups(accessionData.hit_groups)).toEqual([
      accessionData.hit_groups[0],
    ]);
  });
  it("selectReadsFromHitGroups keeps only groups with reads", () => {
    // Both example groups have >=1 read.
    expect(selectReadsFromHitGroups(accessionData.hit_groups)).toHaveLength(2);
  });
});

describe("viz-data generators", () => {
  it("generateCoverageVizData scales x0 by bin size and carries height", () => {
    expect(generateCoverageVizData(accessionData.coverage, 100)).toEqual([
      { x0: 0, length: 12 },
      { x0: 100, length: 4 },
    ]);
  });

  it("generateContigReadVizData falls back to the bin when the hit is small or aggregated", () => {
    // First group is aggregated (contigs+reads > 1) -> use bin [binIndex*size, (binIndex+1)*size].
    // Second group is a single read spanning < binSize -> also use the bin.
    expect(generateContigReadVizData(accessionData.hit_groups, 100)).toEqual([
      [0, 100],
      [100, 200],
    ]);
  });

  it("generateContigReadVizData uses the raw range for a single wide hit", () => {
    // Single contig spanning >= binSize -> keep the actual [start, end].
    const wideSingle = [[1, 0, 7, 300, 900, 500, 0.9, 0, 0, 2]];
    expect(generateContigReadVizData(wideSingle as any, 100)).toEqual([
      [300, 900],
    ]);
  });
});

describe("getSortedAccessionSummaries", () => {
  it("sorts best_accessions by descending score", () => {
    const data = {
      best_accessions: [
        { id: "a", score: 1 },
        { id: "b", score: 9 },
        { id: "c", score: 5 },
      ],
    } as any;
    expect(getSortedAccessionSummaries(data).map(s => s.id)).toEqual([
      "b",
      "c",
      "a",
    ]);
  });
});

describe("getCombinedAccessionDataForSpecies", () => {
  it("flattens each species' best accessions and sums num_accessions", () => {
    const byTaxon = {
      10: {
        best_accessions: [{ id: "x" }],
        num_accessions: 2,
      },
      20: {
        best_accessions: [{ id: "y" }, { id: "z" }],
        num_accessions: 3,
      },
    };
    const species = [
      { taxId: 10, name: "Species Ten", commonName: "ten" },
      { taxId: 20, name: "Species Twenty", commonName: "twenty" },
    ];
    const combined = getCombinedAccessionDataForSpecies(species, byTaxon);
    expect(combined.num_accessions).toBe(5);
    expect(combined.best_accessions).toHaveLength(3);
    // The species name is stamped onto each accession.
    expect(combined.best_accessions[0].taxon_name).toBe("Species Ten");
  });
});

describe("getCoverageVizParams", () => {
  it("returns an empty object when there are no params", () => {
    expect(getCoverageVizParams(null, {})).toEqual({});
  });

  it("aggregates species for a genus-level taxon", () => {
    const byTaxon = {
      10: { best_accessions: [{ id: "x" }], num_accessions: 1 },
    };
    const params = {
      taxId: 99,
      taxName: "Genus",
      taxLevel: "genus",
      taxSpecies: [{ taxId: 10, name: "Sp", commonName: "sp" }],
    };
    const result = getCoverageVizParams(params, byTaxon);
    expect(result.taxonId).toBe(99);
    expect((result.accessionData as any).num_accessions).toBe(1);
  });

  it("uses the single taxon's accession data for a non-genus taxon", () => {
    const accData = { best_accessions: [], num_accessions: 0 };
    const byTaxon = { 42: accData };
    const params = { taxId: 42, taxName: "Species", taxLevel: "species" };
    const result = getCoverageVizParams(params, byTaxon);
    expect(result.accessionData).toBe(accData);
  });
});
