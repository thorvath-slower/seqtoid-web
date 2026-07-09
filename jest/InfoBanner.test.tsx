// CZID-586 (#586) frontend coverage: InfoBanner is the shared empty/info panel
// used across discovery and sample views. It has several optional-content
// branches (title, message, suggestion, single vs array links, listenerLink).
import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import { InfoBanner } from "~/components/common/InfoBanner/InfoBanner";

describe("InfoBanner", () => {
  it("renders title, message and suggestion when provided", () => {
    render(
      React.createElement(InfoBanner, {
        title: "No samples yet",
        message: "This project is empty.",
        suggestion: "Upload one to get started.",
      }),
    );
    expect(screen.getByText("No samples yet")).toBeTruthy();
    expect(screen.getByText("This project is empty.")).toBeTruthy();
    expect(screen.getByText("Upload one to get started.")).toBeTruthy();
  });

  it("renders a single internal link", () => {
    render(
      React.createElement(InfoBanner, {
        title: "t",
        link: { text: "Go home", href: "/home" },
      }),
    );
    expect(screen.getByText("Go home")).toBeTruthy();
  });

  it("renders an array of links, including an external one", () => {
    render(
      React.createElement(InfoBanner, {
        title: "t",
        link: [
          { text: "Internal", href: "/a" },
          { text: "External", href: "https://x.test", external: true },
        ],
      }),
    );
    expect(screen.getByText("Internal")).toBeTruthy();
    expect(screen.getByText("External")).toBeTruthy();
  });

  it("renders a listenerLink and fires its onClick (taking precedence over link)", () => {
    const onClick = jest.fn();
    render(
      React.createElement(InfoBanner, {
        title: "t",
        listenerLink: { text: "Clear filters", onClick },
        link: { text: "should-not-render", href: "/x" },
      }),
    );
    fireEvent.click(screen.getByText("Clear filters"));
    expect(onClick).toHaveBeenCalledTimes(1);
    // link is not rendered because listenerLink takes precedence.
    expect(screen.queryByText("should-not-render")).toBeNull();
  });
});
