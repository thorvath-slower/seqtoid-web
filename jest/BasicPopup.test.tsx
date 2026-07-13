// CZID-586 (#586) frontend coverage: BasicPopup is a thin wrapper over
// semantic-ui-react's Popup used ubiquitously for tooltips.
import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import BasicPopup from "~/components/common/BasicPopup";

describe("BasicPopup", () => {
  it("shows its content on hover of the trigger", async () => {
    render(
      React.createElement(BasicPopup, {
        content: "Helpful hint",
        trigger: React.createElement("span", null, "hover me"),
      }),
    );
    // semantic-ui's Popup opens on hover after a short delay and mounts its
    // content into a portal, so poll for it rather than reading synchronously.
    fireEvent.mouseEnter(screen.getByText("hover me"));
    expect(await screen.findByText("Helpful hint")).toBeTruthy();
  });

  it("carries the inverted/tiny defaults", () => {
    expect((BasicPopup as any).defaultProps.inverted).toBe(true);
    expect((BasicPopup as any).defaultProps.size).toBe("tiny");
    expect((BasicPopup as any).defaultProps.basic).toBe(true);
  });
});
