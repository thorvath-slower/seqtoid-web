import { act, fireEvent, render, screen } from "@testing-library/react";
import React from "react";
import LiveSearchPopBox, {
  SearchResults,
} from "~/components/ui/controls/LiveSearchPopBox";

// Regression test for the geosearch stale-closure bug: the debounced search read the
// `inputValue` state captured by its closure, which lagged one keystroke behind — so
// typing "france" searched "franc" and the plain-text fallback showed "franc". The fix
// passes the typed value through the debounce and guards results by the latest query.
describe("LiveSearchPopBox", () => {
  const PLACEHOLDER = "Search here";

  // Mimics GeoSearchInputBox: no server matches, so the only result is a plain-text
  // fallback built from the query the user typed.
  const plainTextSearch = jest.fn(
    async (query: string): Promise<SearchResults> => ({
      "No Results (Use Plain Text)": {
        name: "No Results (Use Plain Text)",
        results: [{ title: query, name: query }],
      },
    }),
  );

  beforeEach(() => {
    jest.useFakeTimers();
    plainTextSearch.mockClear();
  });
  afterEach(() => {
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
  });

  const type = (input: HTMLElement, value: string) =>
    fireEvent.change(input, { target: { value } });

  it("searches the value the user actually typed, not the previous keystroke", async () => {
    // NOTE: use React.createElement instead of JSX so the `React` import is genuinely
    // referenced — the repo's prettier organize-imports (automatic JSX runtime) would
    // otherwise strip it, but Jest's classic-runtime transform needs React in scope.
    render(
      React.createElement(LiveSearchPopBox, {
        placeholder: PLACEHOLDER,
        onSearchTriggered: plainTextSearch,
        onResultSelect: jest.fn(),
        inputMode: true,
      }),
    );
    const input = screen.getByPlaceholderText(PLACEHOLDER);

    // Two rapid keystrokes: the second lands before the first's debounce fires.
    type(input, "franc");
    type(input, "france");

    await act(async () => {
      jest.advanceTimersByTime(300); // past the 200ms debounce
      await Promise.resolve(); // flush the async onSearchTriggered
    });

    // The bug fired the search with the stale "franc"; the fix searches "france".
    // Since GeoSearchInputBox builds the plain-text fallback from this exact query
    // ({ title: query }), searching "france" is what makes the fallback show "france".
    expect(plainTextSearch).toHaveBeenCalled();
    expect(plainTextSearch).toHaveBeenLastCalledWith("france");
    expect(plainTextSearch).not.toHaveBeenLastCalledWith("franc");
  });
});
