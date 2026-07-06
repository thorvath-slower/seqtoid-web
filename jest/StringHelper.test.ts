// CZID-462 (#498) coverage gap: StringHelper backs client-side email/name validation
// on the auth / user-profile paths (sign-up, invite, profile edit). It had no unit
// coverage. These are pure, deterministic, non-flaky tests.
import StringHelper from "../app/assets/src/helpers/StringHelper";

describe("StringHelper.validateEmail", () => {
  it.each([
    "user@example.com",
    "first.last@sub.domain.org",
    "a+tag@example.co",
    "x@a.io",
    "USER@EXAMPLE.COM",
  ])("accepts valid address %s", email => {
    expect(StringHelper.validateEmail(email)).toBe(true);
  });

  it.each([
    "",
    "plainaddress",
    "@no-local.com",
    "no-at-sign.com",
    "trailing@dot.",
    "spaces in@example.com",
    "double@@example.com",
  ])("rejects invalid address %s", email => {
    expect(StringHelper.validateEmail(email)).toBe(false);
  });
});

describe("StringHelper.capitalizeFirstLetter", () => {
  it("capitalizes the first character", () => {
    expect(StringHelper.capitalizeFirstLetter("hello")).toBe("Hello");
  });

  it("leaves an already-capitalized string unchanged", () => {
    expect(StringHelper.capitalizeFirstLetter("World")).toBe("World");
  });

  it("handles a single character", () => {
    expect(StringHelper.capitalizeFirstLetter("a")).toBe("A");
  });

  it("returns an empty string for empty input", () => {
    // charAt(0) is "" and slice(1) is "" -> ""
    expect(StringHelper.capitalizeFirstLetter("")).toBe("");
  });
});

describe("StringHelper.validateName", () => {
  it.each(["John", "Mary Jane", "Jean-Luc", "a b c"])(
    "accepts valid name %s",
    name => {
      expect(StringHelper.validateName(name)).toBe(true);
    },
  );

  it.each(["", "John1", "O'Brien", "name@", "user_name", "José"])(
    "rejects invalid name %s",
    name => {
      expect(StringHelper.validateName(name)).toBe(false);
    },
  );
});
