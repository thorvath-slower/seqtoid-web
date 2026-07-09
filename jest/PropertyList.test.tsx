// CZID-586 (#586) frontend coverage: PropertyList renders capitalized
// label/description pairs in the gene details ontology panel.
import { render, screen } from "@testing-library/react";
import React from "react";
import PropertyList from "~/components/common/DetailsSidebar/GeneDetailsMode/Ontology/PropertyList/PropertyList";

describe("PropertyList", () => {
  it("capitalizes each label and renders its description", () => {
    render(
      React.createElement(PropertyList, {
        array: [
          { label: "drug class", description: "beta-lactam" },
          { label: "mechanism", description: "efflux" },
        ],
      }),
    );

    // capitalizeFirstLetter("drug class: ") -> "Drug class: "
    expect(screen.getByText("Drug class:")).toBeTruthy();
    expect(screen.getByText("beta-lactam")).toBeTruthy();
    expect(screen.getByText("Mechanism:")).toBeTruthy();
    expect(screen.getByText("efflux")).toBeTruthy();
  });

  it("renders nothing for an empty array", () => {
    const { container } = render(
      React.createElement(PropertyList, { array: [] }),
    );
    expect(container.textContent).toBe("");
  });
});
