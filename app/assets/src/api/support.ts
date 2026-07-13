import {
  Diagnostics,
  QuickReport,
} from "~/components/common/SupportPortal/collectDiagnostics";
import { postWithCSRF } from "./core";

export interface SupportRequestPayload {
  description: string;
  // The minimal, user-facing report (error / task / project / account). This is
  // exactly what the end user sees in the quick-report popup (#440).
  quickReport: QuickReport;
  // The fuller diagnostics set, sent for the support-side payload only. Never
  // surfaced to the end user except behind the "More details" expand.
  diagnostics: Diagnostics;
}

// Submits an in-app support/issue report to the Rails support_requests endpoint (#440).
export const createSupportRequest = ({
  description,
  quickReport,
  diagnostics,
}: SupportRequestPayload) =>
  postWithCSRF("/support_requests", {
    description,
    quick_report: quickReport,
    diagnostics,
  });
