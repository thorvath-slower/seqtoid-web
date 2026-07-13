// CZID-586 (#586) frontend coverage: Footer is the shared site footer with
// static navigation and legal links.
import { render, screen } from "@testing-library/react";
import React from "react";
import { Footer } from "~/components/common/Footer/Footer";

describe("Footer", () => {
  it("renders the primary navigation and legal links", () => {
    render(React.createElement(Footer));
    expect(screen.getByText("Github").getAttribute("href")).toContain(
      "github.com",
    );
    expect(screen.getByText("Careers")).toBeTruthy();
    expect(screen.getByText("Resources")).toBeTruthy();
    expect(screen.getByText("Privacy").getAttribute("href")).toBe("/privacy");
    expect(screen.getByText("Terms").getAttribute("href")).toBe("/terms");
    expect(screen.getByText("Cookie Settings")).toBeTruthy();
  });

  it("links to the homepage via the logo", () => {
    render(React.createElement(Footer));
    expect(
      screen.getByLabelText("Go to the SeqtoID homepage").getAttribute("href"),
    ).toBe("/");
  });
});
