import { Diagnostics } from "~/components/common/SupportPortal/collectDiagnostics";
import { postWithCSRF } from "./core";

export interface SupportRequestPayload {
  description: string;
  diagnostics: Diagnostics;
}

// Submits an in-app support/issue report to the Rails support_requests endpoint (#440).
export const createSupportRequest = ({
  description,
  diagnostics,
}: SupportRequestPayload) =>
  postWithCSRF("/support_requests", {
    description,
    diagnostics,
  });
