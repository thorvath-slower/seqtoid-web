// CZID-586 (#586) frontend coverage: GeneDetailsMode/utils.ts builds the
// external reference links (CARD, PubMed, GenBank, ...) shown in the gene
// details sidebar. generateLinkTo is a pure switch with a distinct arm per
// source plus null-guarded accession arms -- cover every branch.
import {
  generateLinkTo,
  Sources,
  Urls,
} from "~/components/common/DetailsSidebar/GeneDetailsMode/utils";

const ontology = {
  accession: "3000001",
  dnaAccession: "NC_1",
  proteinAccession: "WP_1",
} as any;

describe("generateLinkTo", () => {
  it("links to the CARD ARO page when an accession is present", () => {
    expect(
      generateLinkTo({ geneName: "mecA", ontology, source: Sources.CARD }),
    ).toBe(`${Urls.CARD_ARO}3000001`);
  });

  it("returns null for CARD when no accession", () => {
    expect(
      generateLinkTo({
        geneName: "mecA",
        ontology: { ...ontology, accession: "" },
        source: Sources.CARD,
      }),
    ).toBeNull();
  });

  it("links to the CARD OWL repo", () => {
    expect(
      generateLinkTo({ geneName: "mecA", ontology, source: Sources.OWL }),
    ).toBe(`${Urls.CARD_OWL}`);
  });

  it("builds a PubMed term query", () => {
    expect(
      generateLinkTo({ geneName: "mecA", ontology, source: Sources.PUBMED }),
    ).toBe(`${Urls.PUBMED}?term=mecA`);
  });

  it("builds a Google Scholar query", () => {
    expect(
      generateLinkTo({
        geneName: "mecA",
        ontology,
        source: Sources.GOOGLE_SCHOLAR,
      }),
    ).toBe(`${Urls.GOOGLE_SCHOLAR}mecA`);
  });

  it("links to GenBank nucleotide when a dnaAccession is present, else null", () => {
    expect(
      generateLinkTo({
        geneName: "mecA",
        ontology,
        source: Sources.GENBANK_NUCCORE,
      }),
    ).toBe(`${Urls.GENBANK_NUCCORE}NC_1`);
    expect(
      generateLinkTo({
        geneName: "mecA",
        ontology: { ...ontology, dnaAccession: "" },
        source: Sources.GENBANK_NUCCORE,
      }),
    ).toBeNull();
  });

  it("links to GenBank protein when a proteinAccession is present, else null", () => {
    expect(
      generateLinkTo({
        geneName: "mecA",
        ontology,
        source: Sources.GENBANK_PROTEIN,
      }),
    ).toBe(`${Urls.GENBANK_PROTEIN}WP_1`);
    expect(
      generateLinkTo({
        geneName: "mecA",
        ontology: { ...ontology, proteinAccession: "" },
        source: Sources.GENBANK_PROTEIN,
      }),
    ).toBeNull();
  });

  it("returns an empty string for an unknown source (default arm)", () => {
    expect(
      generateLinkTo({ geneName: "mecA", ontology, source: "Mystery" }),
    ).toBe("");
  });
});
