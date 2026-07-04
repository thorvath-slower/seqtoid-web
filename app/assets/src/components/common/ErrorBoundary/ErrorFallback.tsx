import { Button } from "@czi-sds/components";
import React from "react";
import { openSupportPortal } from "~/components/common/SupportPortal/openSupportPortal";
import Notification from "~ui/notifications/Notification";
import cs from "./error_fallback.scss";
import { FriendlyError, toFriendlyError } from "./knownErrors";

interface ErrorFallbackProps {
  // The error that was caught. Used only to derive a friendly, user-facing
  // message via `toFriendlyError` -- the raw error/stack is never rendered.
  error?: unknown;
  // Called to attempt recovery (re-mount the wrapped subtree). When omitted, or
  // when the error is classified as non-retryable, no retry button is shown.
  onRetry?: () => void;
  // Short label describing the view that failed, e.g. "report" or "heatmap",
  // used to give the message a little context and to pre-fill the support note.
  view?: string;
  // Renders a compact, inline treatment instead of the full-height centered
  // panel. Handy when a boundary wraps a small region rather than a whole page.
  inline?: boolean;
}

// The single, reusable user-facing error state (#466). Given a caught error it
// shows a friendly explanation (mapped from known domain errors -- #458), an
// optional retry, and a "Report a problem" action that opens the in-app
// self-help portal (#440). Never surfaces a raw stack trace.
const ErrorFallback = ({
  error,
  onRetry,
  view,
  inline = false,
}: ErrorFallbackProps) => {
  const friendly: FriendlyError = toFriendlyError(error);
  const showRetry = friendly.retryable && typeof onRetry === "function";

  const handleReportProblem = () => {
    openSupportPortal({
      note: view ? `Error while viewing the ${view}` : "Error in the app",
    });
  };

  return (
    <div
      className={inline ? cs.inlineContainer : cs.container}
      role="alert"
      data-testid="error-fallback"
    >
      <Notification
        type="error"
        displayStyle="flat"
        className={cs.notification}
      >
        <div className={cs.title} data-testid="error-fallback-title">
          {friendly.title}
        </div>
        <div className={cs.message} data-testid="error-fallback-message">
          {friendly.message}
        </div>
        <div className={cs.actions}>
          {showRetry && (
            <Button
              sdsStyle="rounded"
              sdsType="primary"
              onClick={onRetry}
              data-testid="error-fallback-retry"
            >
              Try again
            </Button>
          )}
          <Button
            sdsStyle="rounded"
            sdsType="secondary"
            onClick={handleReportProblem}
            data-testid="error-fallback-report"
          >
            Report a problem
          </Button>
        </div>
      </Notification>
    </div>
  );
};

export default ErrorFallback;
