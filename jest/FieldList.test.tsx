// CZID-586 (#586) frontend coverage: FieldList renders label/value pairs in the
// details sidebar, kebab-casing labels into test ids.
import { render, screen } from "@testing-library/react";
import React from "react";
import FieldList from "~/components/common/DetailsSidebar/FieldList";

describe("FieldList", () => {
  it("renders each field's label and value with kebab-cased test ids", () => {
    render(
      React.createElement(FieldList, {
        fields: [
          { label: "Host Organism", value: "Human" },
          { label: "Sample Type", value: "CSF" },
        ],
      }),
    );

    expect(screen.getByTestId("host-organism-field-label").textContent).toBe(
      "Host Organism",
    );
    expect(screen.getByTestId("host-organism-value").textContent).toBe("Human");
    expect(screen.getByTestId("sample-type-value").textContent).toBe("CSF");
  });

  it("renders a node value", () => {
    render(
      React.createElement(FieldList, {
        fields: [
          {
            label: "Link",
            value: React.createElement("a", { href: "/x" }, "go"),
          },
        ],
      }),
    );
    expect(screen.getByText("go").getAttribute("href")).toBe("/x");
  });
});
