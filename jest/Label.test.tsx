import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import BetaLabel from "~/components/ui/labels/BetaLabel";
import Label from "~/components/ui/labels/Label";

// CZID-586 (#586) frontend coverage wave 2 (shared ui primitives). Label is a thin
// wrapper over semantic-ui-react's Label rendered by many views; BetaLabel composes it.
// Covering these shared primitives earns coverage that compounds across every view that
// imports them.
// NOTE: use React.createElement instead of JSX so the `React` import is genuinely
// referenced -- the repo's prettier organize-imports (automatic JSX runtime) would
// otherwise strip it on commit, but Jest's classic-runtime transform needs React in
// scope. This mirrors the existing jest/LiveSearchPopBox.test.tsx convention.
describe("Label", () => {
  it("renders the provided text", () => {
    render(React.createElement(Label, { text: "my-label" }));
    expect(screen.getByText("my-label")).toBeTruthy();
  });

  it("fires onClick when clicked", () => {
    const onClick = jest.fn();
    render(React.createElement(Label, { text: "clickable", onClick }));
    fireEvent.click(screen.getByText("clickable"));
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it("renders without a text prop (empty label)", () => {
    const { container } = render(
      React.createElement(Label, { className: "bare" }),
    );
    // Still renders the underlying label element even with no text.
    expect(container.querySelector(".bare")).toBeTruthy();
  });
});

describe("BetaLabel", () => {
  it("renders the 'beta' text", () => {
    render(React.createElement(BetaLabel));
    expect(screen.getByText("beta")).toBeTruthy();
  });
});
