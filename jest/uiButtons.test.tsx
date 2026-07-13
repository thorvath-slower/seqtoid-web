import { fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import Button from "~/components/ui/controls/buttons/Button";
import DownloadButton from "~/components/ui/controls/buttons/DownloadButton";
import ErrorButton from "~/components/ui/controls/buttons/ErrorButton";
import PrimaryButton from "~/components/ui/controls/buttons/PrimaryButton";
import SaveButton from "~/components/ui/controls/buttons/SaveButton";
import SecondaryButton from "~/components/ui/controls/buttons/SecondaryButton";
import ShareButton from "~/components/ui/controls/buttons/ShareButton";
import TransparentButton from "~/components/ui/controls/buttons/TransparentButton";

// CZID-586 (#586) shared ui button primitives. PrimaryButton/SecondaryButton/
// TransparentButton are thin wrappers over the base Button; DownloadButton/
// ShareButton/SaveButton/ErrorButton wrap the SDS Button. Only core Jest
// matchers are available (no jest-dom in this repo).
// Classic-runtime JSX needs React in scope; the anchor keeps prettier's
// organize-imports plugin from dropping the import.
const _React: typeof React = React;

describe("Button", () => {
  it("renders plain text content", () => {
    render(<Button text="Plain" />);
    expect(screen.getByText("Plain")).toBeTruthy();
  });

  it("renders an icon/label wrapper with a kebab-cased test id", () => {
    render(
      <Button
        text="My Action"
        icon={<span data-testid="the-icon" />}
        label={<span>lbl</span>}
      />,
    );
    // icon+label path builds a `${kebabCase(text)}-button` test id wrapper.
    expect(screen.getByTestId("my-action-button")).toBeTruthy();
    expect(screen.getByTestId("the-icon")).toBeTruthy();
  });

  it("renders a dropdown arrow when hasDropdownArrow is set", () => {
    const { container } = render(<Button text="Menu" hasDropdownArrow />);
    expect(container.querySelector(".icon-dropdown-arrow")).toBeTruthy();
  });

  it("fires onClick", () => {
    const onClick = jest.fn();
    render(<Button text="Click" onClick={onClick} />);
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalledTimes(1);
  });
});

describe("Button wrappers", () => {
  it("PrimaryButton renders and forwards clicks", () => {
    const onClick = jest.fn();
    render(<PrimaryButton text="Primary" onClick={onClick} />);
    fireEvent.click(screen.getByText("Primary"));
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it("SecondaryButton renders its text", () => {
    render(<SecondaryButton text="Secondary" />);
    expect(screen.getByText("Secondary")).toBeTruthy();
  });

  it("TransparentButton renders with the transparent class", () => {
    const { container } = render(<TransparentButton text="Transparent" />);
    expect(container.querySelector(".transparent-btn")).toBeTruthy();
  });
});

describe("DownloadButton", () => {
  it("renders the default label and fires onClick", () => {
    const onClick = jest.fn();
    render(<DownloadButton onClick={onClick} />);
    const button = screen.getByRole("button");
    expect(screen.getByText("Download")).toBeTruthy();
    fireEvent.click(button);
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it("respects a custom label and the disabled state", () => {
    const onClick = jest.fn();
    render(<DownloadButton text="Export" disabled primary onClick={onClick} />);
    const button = screen.getByRole("button") as HTMLButtonElement;
    expect(screen.getByText("Export")).toBeTruthy();
    expect(button.disabled).toBe(true);
  });
});

describe("ShareButton", () => {
  it("renders and forwards clicks", () => {
    const onClick = jest.fn();
    render(<ShareButton primary onClick={onClick} />);
    expect(screen.getByText("Share")).toBeTruthy();
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it("renders the non-primary variant", () => {
    render(<ShareButton primary={false} onClick={jest.fn()} />);
    expect(screen.getByText("Share")).toBeTruthy();
  });
});

describe("SaveButton", () => {
  it("renders inside its popup and forwards clicks", () => {
    const onClick = jest.fn();
    render(<SaveButton onClick={onClick} />);
    const button = screen.getByRole("button");
    fireEvent.click(button);
    expect(onClick).toHaveBeenCalledTimes(1);
  });
});

describe("ErrorButton", () => {
  it("renders text when provided", () => {
    render(<ErrorButton text="Delete" onClick={jest.fn()} />);
    expect(screen.getByText("Delete")).toBeTruthy();
  });

  it("falls back to children when no text is given, and can start with an icon", () => {
    const onClick = jest.fn();
    render(
      <ErrorButton startIcon="download" onClick={onClick}>
        Remove
      </ErrorButton>,
    );
    expect(screen.getByText("Remove")).toBeTruthy();
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalledTimes(1);
  });
});
