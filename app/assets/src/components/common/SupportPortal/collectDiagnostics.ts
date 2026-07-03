import UserContextType from "~/interface/allowedFeatures";

export interface Diagnostics {
  release: string;
  environment: string;
  userId: string;
  userEmail: string;
  userRole: string;
  url: string;
  route: string;
  userAgent: string;
  language: string;
  viewport: string;
  screen: string;
  timestamp: string;
  timezone: string;
  recentError: string;
}

// The most recent client-side error observed on the page. We record it via a
// lightweight window "error" / "unhandledrejection" listener (installed once by
// SupportPortal) so a user reporting an issue can attach the error that just
// happened without needing to reproduce it. This intentionally avoids reaching
// into Sentry internals, which are not exposed as a queryable client-side store.
let lastClientError: string | null = null;

export const recordClientError = (error: string) => {
  lastClientError = error;
};

export const getLastClientError = (): string | null => lastClientError;

// Collects readily-available, non-sensitive diagnostics about the current
// session, app build, and browser to accompany a support request (#440).
export const collectDiagnostics = (userContext: UserContextType): Diagnostics => {
  const viewport =
    typeof window !== "undefined"
      ? `${window.innerWidth}x${window.innerHeight}`
      : "unknown";
  const screenSize =
    typeof window !== "undefined" && window.screen
      ? `${window.screen.width}x${window.screen.height}`
      : "unknown";

  let timezone = "unknown";
  try {
    timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "unknown";
  } catch {
    timezone = "unknown";
  }

  return {
    release: window.GIT_RELEASE_SHA || "unknown",
    environment: window.ENVIRONMENT || "unknown",
    userId: userContext.userId != null ? String(userContext.userId) : "unknown",
    userEmail: userContext.userEmail || "unknown",
    userRole: userContext.admin ? "admin" : "user",
    url: window.location.href,
    route: window.location.pathname + window.location.search,
    userAgent: navigator.userAgent,
    language: navigator.language,
    viewport,
    screen: screenSize,
    timestamp: new Date().toISOString(),
    timezone,
    recentError: getLastClientError() || "none",
  };
};
