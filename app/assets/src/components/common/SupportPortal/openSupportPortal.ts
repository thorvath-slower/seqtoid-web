// A tiny, dependency-free event bus that lets any part of the app ask the
// in-app self-help portal (#440) to open its "Report an issue" modal. The
// SupportPortal is rendered once at the app shell (index.tsx) and owns its own
// open/close state, so callers (e.g. an error-boundary fallback, a failed
// mutation toast) cannot toggle it via props. Instead they call
// `openSupportPortal()` and the mounted portal, which subscribes on mount,
// opens itself.
//
// This keeps the "contact support" affordance consistent everywhere (#466)
// without threading state through the tree or introducing a global store.

export const SUPPORT_PORTAL_OPEN_EVENT = "csid:open-support-portal";

// Opens the in-app support portal. Optionally records a short, human-readable
// note about what the user was doing / what failed so the quick report is
// pre-populated with useful context. Safe to call in non-browser (test/SSR)
// contexts, where it is a no-op.
export const openSupportPortal = (context?: { note?: string }): void => {
  if (typeof window === "undefined") return;
  window.dispatchEvent(
    new CustomEvent(SUPPORT_PORTAL_OPEN_EVENT, { detail: context ?? {} }),
  );
};

// Subscribe to open requests. Returns an unsubscribe function suitable for a
// React effect cleanup.
export const onOpenSupportPortal = (
  handler: (detail: { note?: string }) => void,
): (() => void) => {
  if (typeof window === "undefined") return () => undefined;
  const listener = (event: Event) => {
    const detail = (event as CustomEvent).detail ?? {};
    handler(detail);
  };
  window.addEventListener(SUPPORT_PORTAL_OPEN_EVENT, listener);
  return () => window.removeEventListener(SUPPORT_PORTAL_OPEN_EVENT, listener);
};
