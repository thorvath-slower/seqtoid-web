// CZID-586 (#586) frontend coverage: ProjectInfoIconTooltip shows public vs
// private project sharing help text behind an info icon tooltip. The SDS
// Tooltip renders its title lazily into a portal (not in jsdom without a real
// popper), so we assert the trigger renders and exercise both isPublic arms of
// the description computation, which runs at render time regardless.
import { render } from "@testing-library/react";
import React from "react";
import ProjectInfoIconTooltip from "~/components/common/ProjectInfoIconTooltip";

describe("ProjectInfoIconTooltip", () => {
  it("renders the info icon trigger for a public project", () => {
    const { container } = render(
      React.createElement(ProjectInfoIconTooltip, { isPublic: true }),
    );
    expect(container.querySelector("svg")).toBeTruthy();
  });

  it("renders the info icon trigger for a private project", () => {
    const { container } = render(
      React.createElement(ProjectInfoIconTooltip, { isPublic: false }),
    );
    expect(container.querySelector("svg")).toBeTruthy();
  });
});
