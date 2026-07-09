import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import AccordionNotification from "~/components/ui/notifications/AccordionNotification";
import IssueGroup from "~/components/ui/notifications/IssueGroup";
import ListNotification from "~/components/ui/notifications/ListNotification";
import Notification from "~/components/ui/notifications/Notification";

// CZID-586 (#586) shared ui notification primitives. Covers Notification's
// per-type icon switch and both close affordances, plus the Accordion/List/
// Issue notifications built on top of it.
// Classic-runtime JSX needs React in scope; the anchor keeps prettier's
// organize-imports plugin from dropping the import.
const _React: typeof React = React;

describe("Notification", () => {
  it("renders each type variant with its icon", () => {
    for (const type of ["success", "info", "warning", "error"] as const) {
      const { container } = render(
        <Notification type={type}>body {type}</Notification>,
      );
      expect(container.querySelector("svg")).toBeTruthy();
    }
  });

  it("shows a Dismiss action and fires onClose when clicked", () => {
    const onClose = jest.fn();
    render(
      <Notification type="info" onClose={onClose}>
        message
      </Notification>,
    );
    fireEvent.click(screen.getByText("Dismiss"));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("shows a close icon instead of Dismiss when closeWithIcon is set", () => {
    const onClose = jest.fn();
    render(
      <Notification
        type="warning"
        onClose={onClose}
        closeWithDismiss={false}
        closeWithIcon
      >
        message
      </Notification>,
    );
    expect(screen.queryByText("Dismiss")).toBeNull();
    fireEvent.click(screen.getByTestId("x-close-icon"));
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});

describe("AccordionNotification", () => {
  it("renders the header and content", () => {
    render(
      <AccordionNotification
        type="warning"
        open
        header={<span>Heads up</span>}
        content={<span>details here</span>}
      />,
    );
    expect(screen.getByText("Heads up")).toBeTruthy();
    expect(screen.getByText("details here")).toBeTruthy();
  });

  it("renders with an onClose dismiss action", () => {
    const onClose = jest.fn();
    render(
      <AccordionNotification
        type="info"
        header={<span>Title</span>}
        onClose={onClose}
      />,
    );
    fireEvent.click(screen.getByText("Dismiss"));
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});

describe("ListNotification", () => {
  it("pluralizes the item count when there is more than one item", () => {
    render(
      <ListNotification
        className="cls"
        onClose={jest.fn()}
        type="error"
        label="Problems found"
        listItems={["one", "two", "three"]}
        listItemName="error"
      />,
    );
    expect(screen.getByText("Problems found")).toBeTruthy();
    expect(screen.getByText("3 errors")).toBeTruthy();
  });

  it("uses the singular form for a single item", () => {
    render(
      <ListNotification
        className="cls"
        onClose={jest.fn()}
        type="warning"
        label="One issue"
        listItems={["only"]}
        listItemName="warning"
      />,
    );
    expect(screen.getByText("1 warning")).toBeTruthy();
  });
});

describe("IssueGroup", () => {
  it("renders the info variant (success icon) with a data table", () => {
    render(
      <IssueGroup
        caption="All good"
        headers={["Col A", "Col B"]}
        rows={[["r1a", "r1b"]]}
        type="info"
        initialOpen
      />,
    );
    expect(screen.getByText("All good")).toBeTruthy();
    expect(screen.getByText("Col A")).toBeTruthy();
  });

  it("renders the error variant (alert icon)", () => {
    const { container } = render(
      <IssueGroup
        caption="Errors"
        headers={["Field"]}
        rows={[["bad value"]]}
        type="error"
        initialOpen
        toggleable
      />,
    );
    expect(screen.getByText("Errors")).toBeTruthy();
    expect(container.querySelector("svg")).toBeTruthy();
  });
});
