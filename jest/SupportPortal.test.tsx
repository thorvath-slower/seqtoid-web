import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import React from "react";
import { UserContext } from "~/components/common/UserContext";
import SupportPortal from "~/components/common/SupportPortal/SupportPortal";
import { createSupportRequest } from "~/api/support";

jest.mock("~/api/support", () => ({
  createSupportRequest: jest.fn(),
}));

const mockedCreate = createSupportRequest as jest.MockedFunction<
  typeof createSupportRequest
>;

const signedInContext = {
  admin: false,
  firstSignIn: false,
  allowedFeatures: [],
  appConfig: {},
  userSignedIn: true,
  userId: 42,
  userName: "Test User",
  userEmail: "test@example.com",
  profileCompleted: true,
};

const renderWithContext = (contextValue: typeof signedInContext) =>
  render(
    <UserContext.Provider value={contextValue}>
      <SupportPortal />
    </UserContext.Provider>,
  );

describe("SupportPortal", () => {
  beforeEach(() => {
    mockedCreate.mockReset();
    // @ts-expect-error minimal stub for the global set by the Rails layout
    window.GIT_RELEASE_SHA = "abc1234";
    // @ts-expect-error minimal stub for the global set by the Rails layout
    window.ENVIRONMENT = "test";
  });

  it("renders the floating button for a signed-in user", () => {
    renderWithContext(signedInContext);
    expect(screen.getByTestId("support-portal-button")).toBeTruthy();
  });

  it("renders nothing for a signed-out user", () => {
    const { container } = renderWithContext({
      ...signedInContext,
      userSignedIn: false,
    });
    expect(container.textContent).toBe("");
  });

  it("opens the panel and shows collected diagnostics", () => {
    renderWithContext(signedInContext);
    fireEvent.click(screen.getByTestId("support-portal-button"));

    const diagnostics = screen.getByTestId("support-portal-diagnostics");
    expect(diagnostics.textContent).toContain("abc1234");
    expect(diagnostics.textContent).toContain("test@example.com");
  });

  it("submits a support request with diagnostics and shows success", async () => {
    mockedCreate.mockResolvedValueOnce({ status: "ok" });
    renderWithContext(signedInContext);

    fireEvent.click(screen.getByTestId("support-portal-button"));
    fireEvent.click(screen.getByTestId("support-portal-submit"));

    await waitFor(() => expect(mockedCreate).toHaveBeenCalledTimes(1));
    const arg = mockedCreate.mock.calls[0][0];
    expect(arg.diagnostics.release).toBe("abc1234");
    expect(arg.diagnostics.userEmail).toBe("test@example.com");
    await screen.findByText(/your report was sent/i);
  });
});
