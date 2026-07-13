// CZID-586 (#586) frontend coverage: LoadingMessage is a shared spinner+text
// primitive rendered by many loading states.
import { render, screen } from "@testing-library/react";
import React from "react";
import LoadingMessage from "~/components/common/LoadingMessage";

describe("LoadingMessage", () => {
  it("renders the provided message", () => {
    render(React.createElement(LoadingMessage, { message: "Loading data..." }));
    expect(screen.getByText("Loading data...")).toBeTruthy();
  });

  it("applies an extra className to the container", () => {
    const { container } = render(
      React.createElement(LoadingMessage, {
        message: "x",
        className: "my-extra-class",
      }),
    );
    expect(container.querySelector(".my-extra-class")).toBeTruthy();
  });

  it("renders without a message without throwing", () => {
    expect(() => render(React.createElement(LoadingMessage, {}))).not.toThrow();
  });
});
