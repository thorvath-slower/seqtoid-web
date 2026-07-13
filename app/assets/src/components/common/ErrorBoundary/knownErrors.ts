// Maps errors that reach a React error boundary to friendly, actionable
// messages (#466). This is the single place that decides what a user is told
// when a view fails to render.
//
// It is deliberately forward-compatible with #458 (domain-errors-as-GraphQL):
// when a domain error carries a machine-readable code (Relay/GraphQL surfaces
// these on `error.extensions.code`, or we may attach `error.code`), we key off
// that code first. Absent a code, we fall back to matching the error name /
// message text so we still do something sensible for today's plain `Error`s.
//
// Whatever we can't classify falls through to a safe generic message -- we
// never show a raw stack trace or a raw server message to a user.

export interface FriendlyError {
  // Short, human title for the fallback ("Something went wrong").
  title: string;
  // One or two sentences explaining what happened, in plain language.
  message: string;
  // Whether re-rendering the view could plausibly recover. Retry is only
  // offered for transient / load-style failures, never for e.g. "not found".
  retryable: boolean;
}

// The generic fallback used when we can't classify the error. Retryable by
// default because most unclassified render failures are transient.
export const GENERIC_ERROR: FriendlyError = {
  title: "Something went wrong",
  message:
    "We hit an unexpected problem displaying this view. You can try again, " +
    "and if it keeps happening, let us know and we'll take a look.",
  retryable: true,
};

// Known domain-error codes (aligned with #458). Kept intentionally small and
// additive: new codes can be appended without touching call sites.
const CODE_MESSAGES: Record<string, FriendlyError> = {
  NOT_FOUND: {
    title: "Not found",
    message:
      "We couldn't find what you were looking for. It may have been moved " +
      "or deleted, or you may not have access to it.",
    retryable: false,
  },
  UNAUTHORIZED: {
    title: "You don't have access",
    message:
      "You don't have permission to view this. If you think this is a " +
      "mistake, contact the project owner or our team.",
    retryable: false,
  },
  FORBIDDEN: {
    title: "You don't have access",
    message:
      "You don't have permission to view this. If you think this is a " +
      "mistake, contact the project owner or our team.",
    retryable: false,
  },
  TIMEOUT: {
    title: "This is taking too long",
    message:
      "The request timed out before it finished. This is usually temporary " +
      "-- please try again.",
    retryable: true,
  },
  NETWORK_ERROR: {
    title: "Connection problem",
    message:
      "We couldn't reach the server. Check your connection and try again.",
    retryable: true,
  },
  RATE_LIMITED: {
    title: "Too many requests",
    message:
      "You've made a lot of requests in a short time. Please wait a moment " +
      "and try again.",
    retryable: true,
  },
  PIPELINE_NOT_READY: {
    title: "Results aren't ready yet",
    message:
      "This sample's results are still being generated. Check back in a few " +
      "minutes.",
    retryable: true,
  },
};

// Fallback text matching for plain Errors that don't carry a code. Ordered by
// specificity; first match wins. Matched case-insensitively against the error
// name + message.
const TEXT_PATTERNS: { pattern: RegExp; code: keyof typeof CODE_MESSAGES }[] = [
  { pattern: /not\s*found|404/i, code: "NOT_FOUND" },
  { pattern: /unauthori[sz]ed|401/i, code: "UNAUTHORIZED" },
  { pattern: /forbidden|403|permission|access denied/i, code: "FORBIDDEN" },
  { pattern: /timed?\s*out|timeout/i, code: "TIMEOUT" },
  { pattern: /network|failed to fetch|networkerror|err_connection/i, code: "NETWORK_ERROR" },
  { pattern: /rate.?limit|429|too many requests/i, code: "RATE_LIMITED" },
  { pattern: /pipeline.*(not\s*ready|in\s*progress|still\s*running)/i, code: "PIPELINE_NOT_READY" },
];

// Pull a machine-readable code off an error, if present. Supports both a plain
// `error.code` and the GraphQL/Relay shape `error.extensions.code` (#458), plus
// the first entry of a Relay `error.source.errors[].extensions.code`.
const extractCode = (error: unknown): string | undefined => {
  if (!error || typeof error !== "object") return undefined;
  const e = error as {
    code?: unknown;
    extensions?: { code?: unknown };
    source?: { errors?: Array<{ extensions?: { code?: unknown } }> };
  };
  if (typeof e.code === "string") return e.code;
  if (e.extensions && typeof e.extensions.code === "string") {
    return e.extensions.code;
  }
  const relayCode = e.source?.errors?.[0]?.extensions?.code;
  if (typeof relayCode === "string") return relayCode;
  return undefined;
};

// Resolve any thrown value into a friendly, user-facing error. Never throws and
// never returns raw error text as the user-facing message.
export const toFriendlyError = (error: unknown): FriendlyError => {
  const code = extractCode(error);
  if (code && CODE_MESSAGES[code]) return CODE_MESSAGES[code];

  const name = error instanceof Error ? error.name : "";
  const message = error instanceof Error ? error.message : String(error ?? "");
  const haystack = `${name} ${message}`;
  const match = TEXT_PATTERNS.find(p => p.pattern.test(haystack));
  if (match) return CODE_MESSAGES[match.code];

  return GENERIC_ERROR;
};
