// CZID-462 (#586) coverage: app/assets/src/components/utils/logUtil.ts
import * as Sentry from "@sentry/browser";
import { logError } from "../app/assets/src/components/utils/logUtil";

jest.mock("@sentry/browser", () => ({
  captureException: jest.fn(),
  captureMessage: jest.fn(),
}));

describe("logUtil.ts logError", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("routes to captureException when an exception is provided", () => {
    const exception = new Error("boom");
    logError({ message: "failed", exception, details: { id: 1 } });
    expect(Sentry.captureException).toHaveBeenCalledWith(exception, {
      extra: { message: "failed", details: { id: 1 } },
    });
    expect(Sentry.captureMessage).not.toHaveBeenCalled();
  });

  it("routes to captureMessage when no exception is provided", () => {
    logError({ message: "just a message", details: { foo: "bar" } });
    expect(Sentry.captureMessage).toHaveBeenCalledWith("just a message", {
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
