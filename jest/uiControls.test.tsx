import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import Checkbox from "~/components/ui/controls/Checkbox";
import ExternalLink from "~/components/ui/controls/ExternalLink";
import FilterTag from "~/components/ui/controls/FilterTag";
import Link from "~/components/ui/controls/Link";
import LoadingBar from "~/components/ui/controls/LoadingBar";
import PlusMinusControl from "~/components/ui/controls/PlusMinusControl";
import Tabs from "~/components/ui/controls/Tabs";
import TermsAgreement from "~/components/ui/controls/TermsAgreement";
import Textarea from "~/components/ui/controls/Textarea";
import Toggle from "~/components/ui/controls/Toggle";

// CZID-586 (#586) frontend coverage wave (shared ui primitives under
// components/ui/controls). These wrappers are imported by nearly every view, so
// covering them and their branch arms compounds coverage across the app.
// NOTE: JSX is fine here (see jest/ErrorBoundary.test.tsx) as long as React is
// imported -- Jest's classic-runtime transform needs React in scope. The anchor
// below keeps prettier's organize-imports plugin from dropping the import.
const _React: typeof React = React;

describe("Toggle", () => {
  it("shows the off label initially and the on label after toggling", () => {
    const onChange = jest.fn();
    const { container } = render(
      <Toggle
        onLabel="On"
        offLabel="Off"
        initialChecked={false}
        onChange={onChange}
      />,
    );
    expect(screen.getByText("Off")).toBeTruthy();
    const input = container.querySelector("input") as HTMLInputElement;
    fireEvent.click(input);
    expect(onChange).toHaveBeenCalledWith("On");
    expect(screen.getByText("On")).toBeTruthy();
  });

  it("honors the controlled isChecked prop over internal state", () => {
    const { container } = render(
      <Toggle
        onLabel="On"
        offLabel="Off"
        initialChecked={false}
        isChecked={true}
      />,
    );
    const input = container.querySelector("input") as HTMLInputElement;
    expect(input.checked).toBe(true);
  });

  it("re-syncs internal state when initialChecked changes (apply-all)", () => {
    const { container, rerender } = render(
      <Toggle onLabel="On" offLabel="Off" initialChecked={false} />,
    );
    expect(screen.getByText("Off")).toBeTruthy();
    rerender(<Toggle onLabel="On" offLabel="Off" initialChecked={true} />);
    const input = container.querySelector("input") as HTMLInputElement;
    expect(input.checked).toBe(true);
  });
});

describe("PlusMinusControl", () => {
  it("fires the plus and minus handlers when enabled", () => {
    const onPlusClick = jest.fn();
    const onMinusClick = jest.fn();
    render(
      <PlusMinusControl
        onPlusClick={onPlusClick}
        onMinusClick={onMinusClick}
      />,
    );
    const buttons = screen.getAllByRole("button");
    expect(buttons).toHaveLength(2);
    fireEvent.click(buttons[0]);
    fireEvent.click(buttons[1]);
    expect(onPlusClick).toHaveBeenCalledTimes(1);
    expect(onMinusClick).toHaveBeenCalledTimes(1);
  });

  it("disables the buttons when the disabled props are set", () => {
    render(<PlusMinusControl plusDisabled minusDisabled />);
    const buttons = screen.getAllByRole("button") as HTMLButtonElement[];
    expect(buttons[0].disabled).toBe(true);
    expect(buttons[1].disabled).toBe(true);
  });
});

describe("Checkbox", () => {
  it("reflects the checked prop and toggles + reports changes on click", () => {
    const onChange = jest.fn();
    render(
      <Checkbox
        checked={true}
        value="v1"
        label="pick me"
        onChange={onChange}
        testId="cb"
      />,
    );
    expect(screen.getByText("pick me")).toBeTruthy();
    const input = screen.getByRole("checkbox") as HTMLInputElement;
    expect(input.checked).toBe(true);
    fireEvent.click(screen.getByTestId("cb"));
    // Toggled from the derived checked=true down to false.
    expect(onChange).toHaveBeenCalledWith("v1", false, expect.anything());
  });

  it("does not fire onChange when disabled", () => {
    const onChange = jest.fn();
    render(
      <Checkbox
        checked={false}
        value="v2"
        onChange={onChange}
        disabled
        testId="cb-disabled"
      />,
    );
    fireEvent.click(screen.getByTestId("cb-disabled"));
    expect(onChange).not.toHaveBeenCalled();
  });
});

describe("LoadingBar", () => {
  // Structure is an outer background div wrapping the inner progress div that
  // carries the inline width; grab the last div to get the inner bar.
  const barWidth = (container: HTMLElement) => {
    const divs = container.querySelectorAll("div");
    return Math.round(parseFloat(divs[divs.length - 1].style.width));
  };

  it("clamps the width to the 0-100% range", () => {
    const { container: over } = render(<LoadingBar percentage={5} />);
    expect(barWidth(over)).toBe(100);
    const { container: under } = render(<LoadingBar percentage={-1} />);
    expect(barWidth(under)).toBe(0);
    const { container: mid } = render(<LoadingBar percentage={0.42} />);
    expect(barWidth(mid)).toBe(42);
  });

  it("renders the error and tiny variants without crashing", () => {
    const { container } = render(
      <LoadingBar percentage={0.5} error tiny showHint />,
    );
    expect(barWidth(container)).toBe(50);
  });
});

describe("FilterTag", () => {
  it("renders the text without a close icon when onClose is absent", () => {
    render(<FilterTag text="my filter" />);
    expect(screen.getByText("my filter")).toBeTruthy();
    expect(screen.queryByTestId("x-close-icon")).toBeNull();
  });

  it("fires onClose when the close icon is clicked", () => {
    const onClose = jest.fn();
    render(<FilterTag text="closable" onClose={onClose} />);
    fireEvent.click(screen.getByTestId("x-close-icon"));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("does not fire onClose when disabled", () => {
    const onClose = jest.fn();
    render(<FilterTag text="locked" onClose={onClose} disabled />);
    fireEvent.click(screen.getByTestId("x-close-icon"));
    expect(onClose).not.toHaveBeenCalled();
  });
});

describe("Textarea", () => {
  it("passes the typed string value to onChange", () => {
    const onChange = jest.fn();
    const { container } = render(<Textarea onChange={onChange} />);
    const textarea = container.querySelector("textarea") as HTMLTextAreaElement;
    fireEvent.change(textarea, { target: { value: "hello" } });
    expect(onChange).toHaveBeenCalledWith("hello");
  });

  it("renders without an onChange handler", () => {
    const { container } = render(<Textarea />);
    const textarea = container.querySelector("textarea") as HTMLTextAreaElement;
    fireEvent.change(textarea, { target: { value: "x" } });
    expect(textarea).toBeTruthy();
  });
});

describe("Tabs", () => {
  it("normalizes string tabs and reports the clicked tab value", () => {
    const onChange = jest.fn();
    render(<Tabs tabs={["Alpha", "Beta"]} value="Alpha" onChange={onChange} />);
    expect(screen.getByText("Alpha")).toBeTruthy();
    fireEvent.click(screen.getByText("Beta"));
    expect(onChange).toHaveBeenCalledWith("Beta");
  });

  it("supports object tabs with label elements", () => {
    const onChange = jest.fn();
    render(
      <Tabs
        tabs={[{ value: "one", label: <span>One label</span> }]}
        value="one"
        onChange={onChange}
        hideBorder
      />,
    );
    fireEvent.click(screen.getByText("One label"));
    expect(onChange).toHaveBeenCalledWith("one");
  });
});

describe("Link / ExternalLink", () => {
  it("renders an href and opens external links in a new tab", () => {
    render(<ExternalLink href="https://example.com">go</ExternalLink>);
    const anchor = screen.getByText("go").closest("a") as HTMLAnchorElement;
    expect(anchor.getAttribute("href")).toBe("https://example.com");
    expect(anchor.getAttribute("target")).toBe("_blank");
  });

  it("renders an internal link with no target and no crash on click", () => {
    render(<Link href="/local">home</Link>);
    const anchor = screen.getByText("home").closest("a") as HTMLAnchorElement;
    expect(anchor.getAttribute("target")).toBeNull();
    fireEvent.click(anchor);
    expect(anchor).toBeTruthy();
  });
});

describe("TermsAgreement", () => {
  it("renders the agreement and forwards checkbox changes", () => {
    const onChange = jest.fn();
    render(<TermsAgreement onChange={onChange} checked={false} />);
    expect(screen.getByTestId("terms-agreement-checkbox")).toBeTruthy();
    expect(screen.getByText("Terms of Service")).toBeTruthy();
    // The Checkbox's clickable wrapper is the terms-agreement testId's child.
    fireEvent.click(screen.getByRole("checkbox"));
    expect(onChange).toHaveBeenCalled();
  });
});
