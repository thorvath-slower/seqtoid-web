// CZID-586 (#586) frontend coverage: LoadingPage is the full-page loading state
// wrapping LoadingMessage in a narrow container.
import { render, screen } from "@testing-library/react";
import React from "react";
import { LoadingPage } from "~/components/common/LoadingPage/LoadingPage";

describe("LoadingPage", () => {
  it("renders the loading message", () => {
    render(React.createElement(LoadingPage));
    expect(screen.getByText("Loading...")).toBeTruthy();
  });
});
