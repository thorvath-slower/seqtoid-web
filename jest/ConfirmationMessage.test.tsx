// CZID-586 (#586) frontend coverage: ConfirmationMessage renders the
// post-registration confirmation / error text with a distinct message per
// errorType.
import { render, screen } from "@testing-library/react";
import React from "react";
import { ConfirmationMessage } from "~/components/common/ConfirmationMessage/ConfirmationMessage";

describe("ConfirmationMessage", () => {
  it("shows the success message when there is no error", () => {
    render(React.createElement(ConfirmationMessage, {}));
    expect(
      screen.getByText(/Form submitted! Please check your email/),
    ).toBeTruthy();
  });

  it("shows the duplicate-email message with register and log in links", () => {
    render(React.createElement(ConfirmationMessage, { errorType: "email" }));
    expect(
      screen.getByText(/existing account associated with the email/),
    ).toBeTruthy();
    expect(screen.getByText("register").getAttribute("href")).toBe("/");
    expect(screen.getByText("log in").getAttribute("href")).toBe(
      "/auth0/login",
    );
  });

  it("shows the unknown-error message with a Help Center link", () => {
    render(React.createElement(ConfirmationMessage, { errorType: "unknown" }));
    expect(screen.getByText(/error in creating your account/)).toBeTruthy();
    expect(screen.getByText("our Help Center")).toBeTruthy();
  });
});
