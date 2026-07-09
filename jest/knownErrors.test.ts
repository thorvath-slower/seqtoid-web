// CZID-586 (#586) frontend coverage: ErrorBoundary/knownErrors.ts is pure
// classification logic that decides what a user is told when a view fails to
// render. Exercising every code, text-pattern, and code-extraction branch here
// is high value -- it compounds through every ErrorBoundary in the app.
import {
  GENERIC_ERROR,
  toFriendlyError,
} from "~/components/common/ErrorBoundary/knownErrors";

describe("knownErrors.toFriendlyError", () => {
  it("falls back to the generic, retryable error for an unclassifiable value", () => {
    expect(toFriendlyError(new Error("totally novel gibberish"))).toBe(
      GENERIC_ERROR,
    );
    expect(GENERIC_ERROR.retryable).toBe(true);
  });

  it("never returns raw error text as the user-facing message", () => {
    const friendly = toFriendlyError(new Error("secret stack detail"));
    expect(friendly.message).not.toContain("secret stack detail");
  });

  describe("machine-readable codes take precedence", () => {
    it.each([
      ["NOT_FOUND", false],
      ["UNAUTHORIZED", false],
      ["FORBIDDEN", false],
      ["TIMEOUT", true],
      ["NETWORK_ERROR", true],
      ["RATE_LIMITED", true],
      ["PIPELINE_NOT_READY", true],
    ])("maps error.code %s (retryable=%s)", (code, retryable) => {
      const err = new Error("ignored text") as Error & { code: string };
      err.code = code;
      const friendly = toFriendlyError(err);
      expect(friendly.title).toBeTruthy();
      expect(friendly.retryable).toBe(retryable);
    });

    it("reads a GraphQL/Relay error.extensions.code (#458)", () => {
      const friendly = toFriendlyError({ extensions: { code: "NOT_FOUND" } });
      expect(friendly.title).toBe("Not found");
      expect(friendly.retryable).toBe(false);
    });

    it("reads the first Relay source.errors[].extensions.code", () => {
      const friendly = toFriendlyError({
        source: { errors: [{ extensions: { code: "TIMEOUT" } }] },
      });
      expect(friendly.retryable).toBe(true);
    });

    it("ignores an unknown code and falls through to text matching", () => {
      const err = new Error("resource not found") as Error & { code: string };
      err.code = "SOME_UNKNOWN_CODE";
      // Unknown code -> not in CODE_MESSAGES -> falls to text pattern "not found".
      expect(toFriendlyError(err).title).toBe("Not found");
    });
  });

  describe("text-pattern fallback for codeless errors", () => {
    it.each([
      ["404 not found", "Not found"],
      ["Request was unauthorized", "You don't have access"],
      ["403 forbidden: permission denied", "You don't have access"],
      ["the request timed out", "This is taking too long"],
      ["Failed to fetch: NetworkError", "Connection problem"],
      ["429 too many requests", "Too many requests"],
      ["pipeline still running", "Results aren't ready yet"],
    ])("classifies %s", (message, expectedTitle) => {
      expect(toFriendlyError(new Error(message)).title).toBe(expectedTitle);
    });

    it("matches case-insensitively against the error name too", () => {
      const err = new Error("boom");
      err.name = "NetworkError";
      expect(toFriendlyError(err).title).toBe("Connection problem");
    });
  });

  describe("non-Error inputs are handled without throwing", () => {
    it("stringifies a bare string and classifies it", () => {
      expect(toFriendlyError("timeout while loading").title).toBe(
        "This is taking too long",
      );
    });

    it("returns generic for null/undefined without throwing", () => {
      expect(toFriendlyError(null)).toBe(GENERIC_ERROR);
      expect(toFriendlyError(undefined)).toBe(GENERIC_ERROR);
    });
  });
});
