import { Button, Icon } from "@czi-sds/components";
import React, { useContext, useEffect, useMemo, useState } from "react";
import { createSupportRequest } from "~/api/support";
import { UserContext } from "~/components/common/UserContext";
import { logError } from "~/components/utils/logUtil";
import Modal from "~ui/containers/Modal";
import Textarea from "~ui/controls/Textarea";
import {
  collectDiagnostics,
  Diagnostics,
  recordClientError,
} from "./collectDiagnostics";
import cs from "./support_portal.scss";

// Human-friendly labels for the diagnostics shown in the panel.
const DIAGNOSTIC_LABELS: { [K in keyof Diagnostics]: string } = {
  release: "App release",
  environment: "Environment",
  userId: "User ID",
  userEmail: "User email",
  userRole: "Role",
  url: "URL",
  route: "Route",
  userAgent: "Browser",
  language: "Language",
  viewport: "Viewport",
  screen: "Screen",
  timestamp: "Timestamp",
  timezone: "Timezone",
  recentError: "Recent error",
};

type SubmitStatus = "idle" | "submitting" | "success" | "error";

// Install a single global listener that remembers the most recent client-side
// error so it can be attached to a support request. Guarded so it only runs once.
let errorListenerInstalled = false;
const installErrorListener = () => {
  if (errorListenerInstalled || typeof window === "undefined") return;
  errorListenerInstalled = true;

  window.addEventListener("error", (event: ErrorEvent) => {
    recordClientError(
      `${event.message} @ ${event.filename}:${event.lineno}:${event.colno}`,
    );
  });
  window.addEventListener(
    "unhandledrejection",
    (event: PromiseRejectionEvent) => {
      const reason =
        event.reason instanceof Error
          ? event.reason.message
          : String(event.reason);
      recordClientError(`Unhandled promise rejection: ${reason}`);
    },
  );
};

// Floating in-app self-help portal (#440). Renders an unobtrusive corner button
// that opens a panel showing session/app diagnostics and lets the user file an
// issue report packaging those diagnostics plus optional free-text.
const SupportPortal = () => {
  const userContext = useContext(UserContext);
  const [open, setOpen] = useState(false);
  const [description, setDescription] = useState("");
  const [status, setStatus] = useState<SubmitStatus>("idle");

  useEffect(() => {
    installErrorListener();
  }, []);

  // Recompute diagnostics each time the panel is opened so route/viewport/errors
  // reflect the current state at report time.
  const diagnostics = useMemo(
    () => (open ? collectDiagnostics(userContext) : null),
    [open, userContext],
  );

  const handleOpen = () => {
    setStatus("idle");
    setDescription("");
    setOpen(true);
  };

  const handleClose = () => setOpen(false);

  const handleSubmit = async () => {
    if (!diagnostics) return;
    setStatus("submitting");
    try {
      await createSupportRequest({ description, diagnostics });
      setStatus("success");
    } catch (error) {
      logError({
        message: "Failed to submit support request",
        details: { error },
      });
      setStatus("error");
    }
  };

  // Only show for authenticated users; the portal is part of the app shell but
  // diagnostics/reporting only make sense in an authenticated session.
  if (!userContext.userSignedIn) return null;

  return (
    <>
      <button
        className={cs.floatingButton}
        onClick={handleOpen}
        aria-label="Help and diagnostics"
        data-testid="support-portal-button"
      >
        <Icon
          className={cs.buttonIcon}
          sdsIcon="questionMark"
          sdsSize="l"
          sdsType="static"
        />
      </button>
      {open && (
        <Modal narrow open onClose={handleClose} xlCloseIcon>
          <div className={cs.panel} data-testid="support-portal-panel">
            <div className={cs.header}>Help &amp; Diagnostics</div>
            <div className={cs.subheader}>
              Having trouble? Review the diagnostics we&apos;ll include, add any
              detail below, and send it to our team.
            </div>

            <div className={cs.sectionLabel}>Describe the issue (optional)</div>
            <Textarea
              className={cs.textarea}
              value={description}
              onChange={setDescription}
              placeholder="What went wrong? What were you trying to do?"
              data-testid="support-portal-description"
            />

            <div className={cs.sectionLabel}>Diagnostics</div>
            <div className={cs.diagnostics} data-testid="support-portal-diagnostics">
              {diagnostics &&
                (Object.keys(diagnostics) as (keyof Diagnostics)[]).map(key => (
                  <div className={cs.diagnosticRow} key={key}>
                    <span className={cs.key}>{DIAGNOSTIC_LABELS[key]}</span>
                    <span className={cs.value} title={diagnostics[key]}>
                      {diagnostics[key]}
                    </span>
                  </div>
                ))}
            </div>

            {status === "success" && (
              <div className={`${cs.statusMessage} ${cs.success}`}>
                Thanks! Your report was sent. Our team will take a look.
              </div>
            )}
            {status === "error" && (
              <div className={`${cs.statusMessage} ${cs.error}`}>
                Sorry, we couldn&apos;t send your report. Please try again.
              </div>
            )}

            <div className={cs.actions}>
              {status === "success" ? (
                <Button
                  sdsStyle="rounded"
                  sdsType="primary"
                  onClick={handleClose}
                >
                  Done
                </Button>
              ) : (
                <>
                  <Button
                    sdsStyle="rounded"
                    sdsType="secondary"
                    onClick={handleClose}
                    disabled={status === "submitting"}
                  >
                    Cancel
                  </Button>
                  <Button
                    sdsStyle="rounded"
                    sdsType="primary"
                    onClick={handleSubmit}
                    disabled={status === "submitting"}
                    data-testid="support-portal-submit"
                  >
                    {status === "submitting" ? "Sending…" : "Report an issue"}
                  </Button>
                </>
              )}
            </div>
          </div>
        </Modal>
      )}
    </>
  );
};

export default SupportPortal;
