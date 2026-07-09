// CZID-586 (#586) frontend coverage: WikipediaLicense is the attribution
// footer shown in the taxon details sidebar.
import { render, screen } from "@testing-library/react";
import React from "react";
import { WikipediaLicense } from "~/components/common/DetailsSidebar/TaxonDetailsMode/WikipediaLicense/WikipediaLicense";

describe("WikipediaLicense", () => {
  it("links to the source article and the CC license", () => {
    render(
      React.createElement(WikipediaLicense, {
        taxonName: "Influenza A virus",
        wikiUrl: "https://en.wikipedia.org/wiki/Influenza_A_virus",
      }),
    );

    const article = screen.getByText("Influenza A virus");
    expect(article.getAttribute("href")).toBe(
      "https://en.wikipedia.org/wiki/Influenza_A_virus",
    );
    expect(
      screen
        .getByText(/Creative Commons Attribution-Share-Alike License 3.0/)
        .getAttribute("href"),
    ).toBe("https://creativecommons.org/licenses/by-sa/3.0/");
  });
});
