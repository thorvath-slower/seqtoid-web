// CZID-586 (#586) frontend coverage: MenuOptionWithDisabledTooltip renders a
// menu item that shows a tooltip only when the option is disabled.
import { render, screen } from "@testing-library/react";
import React from "react";
import { MenuOptionWithDisabledTooltip } from "~/components/common/MenuOptionWithDisabledTooltip/MenuOptionWithDisabledTooltip";

describe("MenuOptionWithDisabledTooltip", () => {
  it("renders the option text for an enabled option", () => {
    render(
      React.createElement(MenuOptionWithDisabledTooltip, {
        option: { value: "a", text: "Alpha", disabled: false } as any,
        optionProps: {},
        tooltipDisplay: React.createElement("span", null, "why disabled"),
      }),
    );
    expect(screen.getByText("Alpha")).toBeTruthy();
  });

  it("renders a disabled option (tooltip title supplied)", () => {
    render(
      React.createElement(MenuOptionWithDisabledTooltip, {
        option: { value: "b", text: "Beta", disabled: true } as any,
        optionProps: {},
        tooltipDisplay: React.createElement("span", null, "why disabled"),
      }),
    );
    expect(screen.getByText("Beta")).toBeTruthy();
  });
});
