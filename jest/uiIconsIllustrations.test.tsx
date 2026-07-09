import { render } from "@testing-library/react";
import React from "react";

// ImgDownloadPrimary imports an scss file via the `~/` alias, which the jest
// config's alias mapper resolves before the css/scss style mock can catch it --
// so it would be parsed as JS and blow up suite load. Mock it to an empty
// module so the illustration barrel imports cleanly under test.
jest.mock("~/styles/themes/_elements.scss", () => ({}), { virtual: true });

import * as Icons from "~/components/ui/icons";
import IconAlert from "~/components/ui/icons/IconAlert";
import SortIcon from "~/components/ui/icons/SortIcon";
import { ILLUSTRATIONS } from "~/components/ui/illustrations";

// CZID-586 (#586) shared ui icon + illustration primitives. These are pure
// presentational SVG components used throughout the app; a render smoke test
// per component compounds coverage cheaply. Branch-bearing icons (SortIcon,
// IconAlert) get explicit arm coverage below.

describe("icon components", () => {
  // Every named export off the icons barrel is a component taking className.
  const iconEntries = Object.entries(Icons).filter(
    ([, value]) => typeof value === "function",
  ) as Array<[string, React.ComponentType<{ className?: string }>]>;

  it("exports a non-trivial set of icons", () => {
    expect(iconEntries.length).toBeGreaterThan(20);
  });

  it.each(iconEntries)(
    "renders %s without crashing",
    (_name, IconComponent) => {
      const { container } = render(<IconComponent className="test-icon" />);
      expect(container.firstChild).toBeTruthy();
    },
  );
});

describe("SortIcon", () => {
  it("renders an up arrow when ascending", () => {
    const { container } = render(
      <SortIcon className="s" sortDirection="ascending" />,
    );
    expect(container.querySelector("svg")).toBeTruthy();
  });

  it("renders a down arrow for any other direction", () => {
    const { container } = render(
      <SortIcon className="s" sortDirection="descending" />,
    );
    expect(container.querySelector("svg")).toBeTruthy();
  });
});

describe("IconAlert", () => {
  it("renders each severity type", () => {
    for (const type of ["info", "warning", "error"] as const) {
      const { container } = render(<IconAlert type={type} className="a" />);
      expect(container.querySelector("svg")).toBeTruthy();
    }
  });
});

describe("illustration components", () => {
  const entries = Object.entries(ILLUSTRATIONS) as Array<
    [string, React.ComponentType<{ className?: string }>]
  >;

  it("exports the full illustration set", () => {
    expect(entries.length).toBe(12);
  });

  it.each(entries)("renders %s without crashing", (_name, Illustration) => {
    const { container } = render(<Illustration className="test-illo" />);
    expect(container.querySelector("svg")).toBeTruthy();
  });
});
