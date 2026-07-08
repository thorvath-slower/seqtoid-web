// #586 (epic #462) coverage: extractChildren separates React children by their
// component type name, returning the first match per requested type (or undefined).
// Pure over a React element tree.
import React from "react";
import extractChildren from "../app/assets/src/components/utils/extractChildren";

function Header() {
  return null;
}
function Footer() {
  return null;
}
function Body() {
  return null;
}

describe("extractChildren", () => {
  it("returns the first child matching each requested type in order", () => {
    const children = [<Header key="h" />, <Body key="b" />, <Footer key="f" />];
    const [header, footer] = extractChildren(children, ["Header", "Footer"]);
    expect((header as React.ReactElement).type).toBe(Header);
    expect((footer as React.ReactElement).type).toBe(Footer);
  });

  it("returns undefined for a requested type with no matching child", () => {
    const [missing] = extractChildren([<Header key="h" />], ["Footer"]);
    expect(missing).toBeUndefined();
  });

  it("returns the first of multiple children of the same type", () => {
    const first = <Body key="1" data-id="first" />;
    const second = <Body key="2" data-id="second" />;
    const [body] = extractChildren([first, second], ["Body"]);
    expect((body as React.ReactElement).props["data-id"]).toBe("first");
  });
});
