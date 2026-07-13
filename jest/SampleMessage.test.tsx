// CZID-586 (#586) frontend coverage: SampleMessage is the shared sample-status
// message block (e.g. "waiting", "failed") shown on sample report pages.
import { render, screen } from "@testing-library/react";
import React from "react";
import SampleMessage from "~/components/common/SampleMessage/SampleMessage";

describe("SampleMessage", () => {
  it("renders status, message, subtitle and the link text", () => {
    render(
      React.createElement(SampleMessage, {
        status: "IN PROGRESS",
        message: "Your sample is being processed.",
        subtitle: "This may take a while.",
        type: "inProgress",
        link: "/help",
        linkText: "Learn more",
      }),
    );

    expect(screen.getByTestId("sample-message")).toBeTruthy();
    expect(screen.getByText("IN PROGRESS")).toBeTruthy();
    expect(screen.getByText("Your sample is being processed.")).toBeTruthy();
    expect(screen.getByText("This may take a while.")).toBeTruthy();
    expect(screen.getByText("Learn more")).toBeTruthy();
  });

  it("renders without link text (no trailing arrow branch)", () => {
    render(
      React.createElement(SampleMessage, {
        status: "DONE",
        message: "Complete",
        type: "success",
      }),
    );
    expect(screen.getByText("DONE")).toBeTruthy();
    expect(screen.queryByText("Learn more")).toBeNull();
  });
});
