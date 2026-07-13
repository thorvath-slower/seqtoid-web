// CZID-586 (#586) frontend coverage: BlankScreenMessage is a shared empty-state
// presentational component used across views.
import { render, screen } from "@testing-library/react";
import React from "react";
import BlankScreenMessage from "~/components/common/BlankScreenMessage";

describe("BlankScreenMessage", () => {
  it("renders the message, tagline, icon, and applies the text width", () => {
    render(
      React.createElement(BlankScreenMessage, {
        icon: React.createElement("span", { "data-testid": "icon" }, "i"),
        message: "Nothing here",
        tagline: "Try adding a sample",
        textWidth: 320,
      }),
    );

    expect(screen.getByText("Nothing here")).toBeTruthy();
    expect(screen.getByText("Try adding a sample")).toBeTruthy();
    expect(screen.getByTestId("icon")).toBeTruthy();
    expect(screen.getByText("Nothing here").parentElement?.style.width).toBe(
      "320px",
    );
  });

  it("accepts a node tagline", () => {
    render(
      React.createElement(BlankScreenMessage, {
        icon: React.createElement("span", null, "i"),
        message: "Empty",
        tagline: React.createElement("a", { href: "/x" }, "link tagline"),
        textWidth: 100,
      }),
    );
    expect(screen.getByText("link tagline").getAttribute("href")).toBe("/x");
  });
});
