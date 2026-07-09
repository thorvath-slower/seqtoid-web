import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import ColumnHeaderTooltip from "~/components/ui/containers/ColumnHeaderTooltip";
import HelpIcon from "~/components/ui/containers/HelpIcon";
import EditableInput from "~/components/ui/controls/EditableInput";
import Input from "~/components/ui/controls/Input";
import { Menu, MenuItem } from "~/components/ui/controls/Menu";
import { EmptyTable } from "~/components/ui/Table/components/EmptyTable/EmptyTable";
import { TooltipText } from "~/components/ui/Table/components/SortableHeader/components/TooltipText/TooltipText";

// CZID-586 (#586) additional shared ui primitives: inputs, menu wrappers,
// tooltip helpers, and the table loading placeholder. Only core Jest matchers
// are available (no jest-dom).
// Classic-runtime JSX needs React in scope; the anchor keeps prettier's
// organize-imports plugin from dropping the import.
const _React: typeof React = React;

describe("Input", () => {
  it("forwards the typed value to onChange", () => {
    const onChange = jest.fn();
    const { container } = render(<Input onChange={onChange} />);
    const input = container.querySelector("input") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "abc" } });
    expect(onChange).toHaveBeenCalledWith("abc");
  });

  it("sets a non-standard autocomplete when autocomplete is disabled", () => {
    const { container } = render(<Input disableAutocomplete />);
    const input = container.querySelector("input") as HTMLInputElement;
    expect(input.getAttribute("autocomplete")).toBe("idseq-ui");
  });
});

describe("Menu / MenuItem", () => {
  it("renders menu items", () => {
    render(
      <Menu>
        <MenuItem>First</MenuItem>
        <MenuItem>Second</MenuItem>
      </Menu>,
    );
    expect(screen.getByText("First")).toBeTruthy();
    expect(screen.getByText("Second")).toBeTruthy();
  });
});

describe("TooltipText", () => {
  it("returns null when there are no tooltip strings", () => {
    const { container } = render(<TooltipText />);
    expect(container.firstChild).toBeNull();
  });

  it("renders bold + regular text and a link when provided", () => {
    render(
      <TooltipText
        tooltipStrings={{
          boldText: "Metric",
          regularText: "what it means",
          link: { href: "/docs", linkText: "Read docs" },
        }}
      />,
    );
    expect(screen.getByText("Metric")).toBeTruthy();
    expect(screen.getByText("Read docs")).toBeTruthy();
  });

  it("omits the link when none is provided", () => {
    render(
      <TooltipText tooltipStrings={{ boldText: "B", regularText: "R" }} />,
    );
    expect(screen.getByText("B")).toBeTruthy();
    expect(screen.queryByText("Read docs")).toBeNull();
  });
});

describe("EmptyTable", () => {
  // NOTE: the component uses the non-standard `data-test-id` attribute (hyphen),
  // not `data-testid`, so query the raw attribute.
  const loadingCells = (container: HTMLElement) =>
    container.querySelectorAll('[data-test-id="loading-cell"]');

  it("renders a loading cell per column across the placeholder rows", () => {
    const { container } = render(<EmptyTable numOfColumns={3} />);
    // 10 placeholder rows * 3 columns each.
    expect(loadingCells(container)).toHaveLength(30);
  });

  it("renders no cells when there are zero columns", () => {
    const { container } = render(<EmptyTable numOfColumns={0} />);
    expect(loadingCells(container)).toHaveLength(0);
  });
});

describe("HelpIcon", () => {
  it("renders the help trigger and fires analytics on hover", () => {
    const { container } = render(
      <HelpIcon
        text="some help"
        analyticsEventName="Help_hovered"
        className="help-trigger"
      />,
    );
    const trigger = container.querySelector(".help-trigger") as HTMLElement;
    expect(trigger).toBeTruthy();
    // Should not throw when the analytics trackEvent fires on mouse enter.
    fireEvent.mouseEnter(trigger);
    expect(container.querySelector("svg")).toBeTruthy();
  });
});

describe("ColumnHeaderTooltip", () => {
  it("renders its content (title, body, link) when open", () => {
    render(
      <ColumnHeaderTooltip
        open
        trigger={<span>trigger</span>}
        title="Score"
        content="explanation"
        link="/learn"
      />,
    );
    expect(screen.getByTestId("column-tooltip")).toBeTruthy();
    expect(screen.getByText("Learn more.")).toBeTruthy();
  });
});

describe("EditableInput", () => {
  it("shows the current value and reveals an input when clicked", () => {
    const onDoneEditing = jest.fn(() => Promise.resolve(["", ""] as ["", ""]));
    const getWarningMessage = jest.fn(() => "");
    const { container } = render(
      <EditableInput
        value="current"
        onDoneEditing={onDoneEditing}
        getWarningMessage={getWarningMessage}
      />,
    );
    expect(screen.getByText("current")).toBeTruthy();
    // Enter edit mode by clicking the display.
    fireEvent.click(screen.getByText("current"));
    const input = container.querySelector("input") as HTMLInputElement;
    expect(input).toBeTruthy();
    fireEvent.change(input, { target: { value: "edited" } });
    expect(getWarningMessage).toHaveBeenCalledWith("edited");
  });
});
