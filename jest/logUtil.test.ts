// #586 (epic #462) coverage: logUtil.logError routes to Sentry, choosing
// captureException when an exception is present and captureMessage otherwise.
// Both arms and the payload shaping are pinned with a mocked Sentry transport.
import * as Sentry from "@sentry/browser";
import { logError } from "../app/assets/src/components/utils/logUtil";

jest.mock("@sentry/browser", () => ({
  captureException: jest.fn(),
  captureMessage: jest.fn(),
}));

describe("logError", () => {
  beforeEach(() => jest.clearAllMocks());

  it("captures the exception with message and details as extra", () => {
    const err = new Error("boom");
    logError({ message: "failed", exception: err, details: { id: 1 } });

    expect(Sentry.captureException).toHaveBeenCalledWith(err, {
      extra: { message: "failed", details: { id: 1 } },
    });
    expect(Sentry.captureMessage).not.toHaveBeenCalled();
  });

  it("captures a message with details as extra when no exception is given", () => {
    logError({ message: "just a note", details: { foo: "bar" } });

    expect(Sentry.captureMessage).toHaveBeenCalledWith("just a note", {
      extra: { foo: "bar" },
    });
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it("defaults details to an empty object", () => {
    logError({ message: "no details" });
    expect(Sentry.captureMessage).toHaveBeenCalledWith("no details", {
      extra: {},
    });
  });
});
