import { render, screen } from "@testing-library/react";
import React from "react";
import AnnotationLabel from "~/components/ui/labels/AnnotationLabel";
import PathogenLabel from "~/components/ui/labels/PathogenLabel";
import StatusLabel from "~/components/ui/labels/StatusLabel";

// CZID-586 (#586) shared ui label primitives. Label/BetaLabel are already
// covered in jest/Label.test.tsx; this exercises StatusLabel, AnnotationLabel,
// and PathogenLabel including their tooltip / static / dimmed branch arms.
// Classic-runtime JSX needs React in scope; the anchor keeps prettier's
// organize-imports plugin from dropping the import.
const _React: typeof React = React;

describe("StatusLabel", () => {
  it("renders the status text without a tooltip", () => {
    render(<StatusLabel status="Complete" type="success" />);
    expect(screen.getByText("Complete")).toBeTruthy();
  });

  it("wraps the label in a tooltip when tooltipText is provided", () => {
    render(<StatusLabel status="Failed" type="error" tooltipText="It broke" />);
    // The label itself is the popup trigger, so its text still renders.
    expect(screen.getByText("Failed")).toBeTruthy();
  });

  it("renders the inline variant with the default type", () => {
    render(<StatusLabel status="Info" inline />);
    expect(screen.getByText("Info")).toBeTruthy();
  });
});

describe("AnnotationLabel", () => {
  it("renders the interactive (non-static) variant", () => {
    const { container } = render(<AnnotationLabel type="hit" />);
    expect(container.querySelector("svg")).toBeTruthy();
  });

  it("renders each static annotation type without crashing", () => {
    for (const type of ["hit", "not_a_hit", "inconclusive", "none"] as const) {
      const { container } = render(<AnnotationLabel type={type} isStatic />);
      expect(container.querySelector("svg")).toBeTruthy();
    }
  });

  it("returns the bare label (no popup) when hideTooltip is set", () => {
    const { container } = render(<AnnotationLabel type="hit" hideTooltip />);
    expect(container.querySelector("svg")).toBeTruthy();
  });
});

describe("PathogenLabel", () => {
  it("renders the known-pathogen label text", () => {
    render(<PathogenLabel type="knownPathogen" />);
    expect(screen.getByTestId("pathogen-label")).toBeTruthy();
    expect(screen.getByText("Known Pathogen")).toBeTruthy();
  });

  it("renders the dimmed variant", () => {
    render(<PathogenLabel type="knownPathogen" isDimmed />);
    expect(screen.getByTestId("pathogen-label")).toBeTruthy();
  });
});
