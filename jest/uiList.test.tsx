import { render, screen } from "@testing-library/react";
import React from "react";
import List from "~/components/ui/List";

// CZID-586 (#586) shared ui List primitive. Covers the ordered/unordered branch
// and the dynamic (nanoid keys) vs index-keyed branch.
// NOTE: JSX here uses the classic runtime, so React must stay in scope. The
// explicit React.ReactElement annotations below keep the import referenced so
// prettier's organize-imports plugin cannot strip it (see jest/Label.test.tsx).

describe("List", () => {
  const items: React.ReactElement[] = [
    <span key="a">first</span>,
    <span key="b">second</span>,
  ];

  it("renders an unordered list by default", () => {
    const { container } = render(<List listItems={items} />);
    expect(container.querySelector("ul")).toBeTruthy();
    expect(container.querySelector("ol")).toBeNull();
    expect(container.querySelectorAll("li")).toHaveLength(2);
    expect(screen.getByText("first")).toBeTruthy();
  });

  it("renders an ordered list when ordered is set", () => {
    const { container } = render(<List ordered listItems={items} />);
    expect(container.querySelector("ol")).toBeTruthy();
    expect(container.querySelector("ul")).toBeNull();
  });

  it("renders with dynamic (nanoid) keys and the spacing variants", () => {
    const { container } = render(
      <List
        dynamic
        listItems={items}
        smallSpacing
        xsmallSpacing={false}
        xxsmallSpacing
        listClassName="my-list"
        itemClassName="my-item"
      />,
    );
    expect(container.querySelectorAll("li")).toHaveLength(2);
    expect(container.querySelector(".my-list")).toBeTruthy();
  });
});
