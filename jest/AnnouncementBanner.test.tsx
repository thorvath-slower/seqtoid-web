// CZID-586 (#586) frontend coverage: AnnouncementBanner shows a dismissible
// banner gated on a `visible` prop and a localStorage "dismissed" flag.
import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import AnnouncementBanner from "~/components/common/AnnouncementBanner";

describe("AnnouncementBanner", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("does not render when not visible", () => {
    const { container } = render(
      React.createElement(AnnouncementBanner, {
        id: "test-1",
        visible: false,
        message: "Heads up",
      }),
    );
    expect(container.firstChild).toBeNull();
  });

  it("renders when visible and not previously dismissed", () => {
    render(
      React.createElement(AnnouncementBanner, {
        id: "test-2",
        visible: true,
        message: "Heads up",
      }),
    );
    expect(screen.getAllByText("Heads up").length).toBeGreaterThan(0);
  });

  it("stays hidden when it was already dismissed in localStorage", () => {
    localStorage.setItem("dismissedAnnouncementBanner-test-3", "true");
    const { container } = render(
      React.createElement(AnnouncementBanner, {
        id: "test-3",
        visible: true,
        message: "Heads up",
      }),
    );
    expect(container.firstChild).toBeNull();
  });

  it("dismisses on close, hiding the banner and persisting the flag", () => {
    const { container } = render(
      React.createElement(AnnouncementBanner, {
        id: "test-4",
        visible: true,
        message: "Heads up",
        inverted: true,
      }),
    );
    // The close icon (IconCloseSmall) is the last svg in the banner; the alert
    // icon is the first. Click the last one to dismiss.
    const svgs = container.querySelectorAll("svg");
    const closeIcon = svgs[svgs.length - 1];
    expect(closeIcon).toBeTruthy();
    fireEvent.click(closeIcon as Element);
    expect(container.firstChild).toBeNull();
    expect(localStorage.getItem("dismissedAnnouncementBanner-test-4")).toBe(
      "true",
    );
  });
});
