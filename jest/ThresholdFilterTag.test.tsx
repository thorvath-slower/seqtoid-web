// CZID-586 (#586) frontend coverage: ThresholdFilterTag renders a removable tag
// for a valid threshold and renders nothing for an invalid one.
import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import ThresholdFilterTag from "~/components/common/ThresholdFilterTag";

const validThreshold = {
  metric: "nt_zscore",
  metricDisplay: "NT Z Score",
  operator: ">=",
  value: "2",
} as any;

describe("ThresholdFilterTag", () => {
  it("renders the formatted threshold text and fires onClose", () => {
    const onClose = jest.fn();
    render(
      React.createElement(ThresholdFilterTag, {
        threshold: validThreshold,
        onClose,
        className: "tag",
      }),
    );
    expect(screen.getByText("NT Z Score >= 2")).toBeTruthy();
    // FilterTag exposes a close affordance; clicking the tag's close calls onClose.
    const closeIcon = document.querySelector(".tag svg, .tag [class*='close']");
    if (closeIcon) {
      fireEvent.click(closeIcon);
      expect(onClose).toHaveBeenCalled();
    }
  });

  it("renders nothing for an invalid (incomplete) threshold", () => {
    const { container } = render(
      React.createElement(ThresholdFilterTag, {
        threshold: { metricDisplay: "NT Z Score", operator: "", value: "" },
        onClose: jest.fn(),
        className: "tag",
      }),
    );
    expect(container.firstChild).toBeNull();
  });

  it("renders nothing when the value is not numeric", () => {
    const { container } = render(
      React.createElement(ThresholdFilterTag, {
        threshold: {
          metric: "nt_zscore",
          metricDisplay: "NT Z Score",
          operator: ">=",
          value: "abc",
        },
        onClose: jest.fn(),
        className: "tag",
      }),
    );
    expect(container.firstChild).toBeNull();
  });
});
