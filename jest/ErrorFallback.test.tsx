// CZID-586 (#586) frontend coverage: ErrorFallback is the reusable user-facing
// error state (#466). ErrorBoundary.test covers it via the boundary; these
// direct tests pin the retry/inline branches that depend on props rather than a
// thrown error.
import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import ErrorFallback from "~/components/common/ErrorBoundary/ErrorFallback";
import { onOpenSupportPortal } from "~/components/common/SupportPortal/openSupportPortal";

describe("ErrorFallback", () => {
  it("shows a retry button for a retryable error when onRetry is provided", () => {
    const onRetry = jest.fn();
    render(
      React.createElement(ErrorFallback, {
        error: new Error("network went down"),
        onRetry,
        view: "report",
      }),
    );
    fireEvent.click(screen.getByTestId("error-fallback-retry"));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  it("hides retry when onRetry is omitted, even for a retryable error", () => {
    render(
      React.createElement(ErrorFallback, {
        error: new Error("network went down"),
      }),
    );
    expect(screen.queryByTestId("error-fallback-retry")).toBeNull();
    // Contact-support is always offered.
    expect(screen.getByTestId("error-fallback-report")).toBeTruthy();
  });

  it("hides retry for a non-retryable error even with onRetry", () => {
    const err = new Error("nope") as Error & { code: string };
    err.code = "NOT_FOUND";
    render(
      React.createElement(ErrorFallback, { error: err, onRetry: jest.fn() }),
    );
    expect(screen.queryByTestId("error-fallback-retry")).toBeNull();
  });

  it("opens the support portal with the view in the note when reporting", () => {
    const handler = jest.fn();
    const unsubscribe = onOpenSupportPortal(handler);
    render(
      React.createElement(ErrorFallback, {
        error: new Error("boom"),
        view: "heatmap",
      }),
    );
    fireEvent.click(screen.getByTestId("error-fallback-report"));
    expect(handler.mock.calls[0][0].note).toContain("heatmap");
    unsubscribe();
  });

  it("renders in inline mode without throwing", () => {
    expect(() =>
      render(
        React.createElement(ErrorFallback, {
          error: new Error("boom"),
          inline: true,
        }),
      ),
    ).not.toThrow();
    expect(screen.getByTestId("error-fallback")).toBeTruthy();
  });
});
