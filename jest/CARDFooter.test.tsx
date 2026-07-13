// CZID-586 (#586) frontend coverage: CARDFooter renders the CARD ontology
// attribution footer in the gene details sidebar.
import { render, screen } from "@testing-library/react";
import React from "react";
import CARDFooter from "~/components/common/DetailsSidebar/GeneDetailsMode/Ontology/CARDLicense/CARDFooter";

describe("CARDFooter", () => {
  it("renders the CARD ontology link and disclaimer", () => {
    render(
      React.createElement(CARDFooter, {
        geneName: "mecA",
        ontology: { accession: "3000001" } as any,
      }),
    );
    expect(
      screen.getByText("CARD Antibiotic Resistance Ontology"),
    ).toBeTruthy();
    expect(screen.getByText(/most recent CARD database/)).toBeTruthy();
    expect(
      screen
        .getByText(/Creative Commons CC-BY license version 4.0/)
        .getAttribute("href"),
    ).toBe("https://creativecommons.org/licenses/by/4.0/");
  });
});
