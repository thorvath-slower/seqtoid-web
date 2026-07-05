import cx from "classnames";
import { forEach, sumBy, values } from "lodash/fp";
import React, { useEffect, useRef, useState } from "react";
import { BareDropdown } from "~ui/controls/dropdowns";
import Input from "~ui/controls/Input";
import cs from "./live_search_pop_box.scss";

type SearchResult = {
  title: string;
  name: number | string;
  description?: string;
  [key: string]: any;
};

interface SearchCategory {
  name: string;
  results: SearchResult[];
}

export interface SearchResults {
  [key: string]: SearchCategory;
}

interface LiveSearchPopBoxProps {
  className?: string;
  delayTriggerSearch?: number;
  inputClassName?: string;
  inputMode?: boolean;
  minChars?: number;
  onResultSelect?(params: any): void;
  onSearchTriggered?(query: string): SearchResults | Promise<SearchResults>;
  placeholder?: string;
  rectangular?: boolean;
  value?: string;
  icon?: string;
  shouldSearchOnFocus?: boolean;
}

const LiveSearchPopBox = ({
  className,
  delayTriggerSearch = 200,
  inputClassName,
  minChars = 2,
  placeholder = "Search",
  rectangular = false,
  inputMode = false,
  icon = "search",
  shouldSearchOnFocus = false,
  onResultSelect,
  onSearchTriggered,
  value,
}: LiveSearchPopBoxProps) => {
  const [latestTimerId, setLatestTimerId] = useState<any>(null);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [isFocused, setIsFocused] = useState<boolean>(false);
  const [results, setResults] = useState<SearchResults>({});
  const [inputValue, setInputValue] = useState<string>("");
  // The query for the most recently requested search. Used to (a) run the search on the
  // value the user actually typed — not a stale `inputValue` captured by the debounced
  // closure, which lagged one keystroke behind (so "france" searched "franc" and the
  // plain-text fallback showed "franc") — and (b) discard out-of-order responses.
  const latestQueryRef = useRef<string>("");

  // If the value has changed, reset the input value.
  // Store the prevValue to detect whether the value has changed.
  // CZID-314: coerce undefined/null to "" so an empty field always has a *string* inputValue.
  // Otherwise hasEnoughChars() below evaluates `undefined >= minChars` — which is false even for
  // minChars=0 — so the shouldSearchOnFocus search never fires and the dropdown never opens on click
  // (it only worked once a keystroke made inputValue a string). See SampleTypeSearchBox (minChars=0).
  useEffect(() => {
    setInputValue(value ?? "");
  }, [value]);

  const handleKeyDown = keyEvent => {
    // Pressing enter selects what they currently typed.
    if (keyEvent.key === "Enter" && inputMode) {
      handleResultSelect({
        result: inputValue,
        currentEvent: {},
      });
    }
  };

  const closeDropdown = () => {
    setIsLoading(false);
    setIsFocused(false);
  };

  const handleResultSelect = ({ currentEvent, result }) => {
    setInputValue(result.title);
    onResultSelect && onResultSelect({ currentEvent, result });
    closeDropdown();
  };

  const triggerSearch = async (query: string) => {
    // @ts-expect-error CZID-8698 expect strictNullCheck error: error TS2722
    const searchResults = await onSearchTriggered(query);

    // Only apply if this is still the latest requested query; drop stale/out-of-order
    // responses so an earlier "franc" search can't overwrite the current "france" one.
    if (query === latestQueryRef.current) {
      setIsLoading(false);
      setResults(searchResults);
    }
  };

  const handleSearchChange = value => {
    setInputValue(value);
    latestQueryRef.current = value;

    // check minimum requirements for value
    const parsedValue = value.trim();
    if (parsedValue.length >= minChars) {
      setIsFocused(true);
      setIsLoading(true);

      if (latestTimerId) {
        clearTimeout(latestTimerId);
      }

      // Pass `value` explicitly so the debounced search runs on exactly what the user
      // typed — not the `inputValue` state, which the closure captured one keystroke ago.
      const newTimerId = setTimeout(
        () => triggerSearch(value),
        delayTriggerSearch,
      );
      setLatestTimerId(newTimerId);
    } else {
      // Below the minimum: stop loading and clear any stale results so the dropdown
      // doesn't linger on a previous query's suggestions.
      setIsLoading(false);
      setResults({});
    }
  };

  const renderSearchBox = () => (
    <div onFocus={handleFocus} onBlur={handleBlur}>
      <Input
        className={cx(
          cs.searchInput,
          rectangular && cs.rectangular,
          inputClassName,
        )}
        icon={icon}
        loading={isLoading}
        placeholder={placeholder}
        onChange={handleSearchChange}
        onKeyPress={handleKeyDown}
        value={inputValue}
        disableAutocomplete
      />
    </div>
  );

  const handleFocus = () => {
    if (hasEnoughChars() && shouldSearchOnFocus) {
      handleSearchChange(inputValue);
    }

    setIsFocused(true);
  };

  // If a user selects an option, handleResultSelect will run and update props.value before this function runs.
  // So inputValue will equal props.value when this function runs and onResultSelect will not be called, which is correct.
  const handleBlur = () => {
    // If the user has changed the input without selecting an option, select what they currently typed as plain-text.
    if (onResultSelect && inputValue !== value) {
      onResultSelect({ result: inputValue });
    }

    closeDropdown();
  };

  const buildItem = (categoryKey, result, index) => (
    <BareDropdown.Item
      key={`${categoryKey}-${result.name}`}
      text={
        <div className={cs.entry}>
          <div className={cs.title}>{result.title}</div>
          {result.description && (
            <div className={cs.description}>{result.description}</div>
          )}
        </div>
      }
      onMouseDown={currentEvent => {
        // use onMouseDown instead of onClick to work with handleBlur
        handleResultSelect({ currentEvent, result });
      }}
      value={`${categoryKey}-${index}`}
    />
  );

  const buildSectionHeader = name => (
    <div key={name} className={cs.category}>
      {name}
    </div>
  );

  const renderDropdownItems = () => {
    // @ts-expect-error Property 'convert' does not exist on type 'LodashForEach'.ts(2339)
    const uncappedForEach = forEach.convert({ cap: false });
    const items = [];
    uncappedForEach((category, key) => {
      // @ts-expect-error CZID-8698 expect strictNullCheck error: error TS2345
      items.push(buildSectionHeader(category.name));
      uncappedForEach((result, index) => {
        // @ts-expect-error CZID-8698 expect strictNullCheck error: error TS2345
        items.push(buildItem(key, result, index));
      }, category.results);
    }, results);

    return items;
  };

  const getResultsLength = () => {
    return sumBy(cat => cat?.results?.length, values(results));
  };

  // Null-safe: an undefined inputValue must not make this `undefined >= minChars` (always false).
  const hasEnoughChars = () => (inputValue?.trim()?.length ?? 0) >= minChars;
  const shouldOpen = getResultsLength() && isFocused && hasEnoughChars();

  return (
    <BareDropdown
      className={cx(
        cs.liveSearchPopBox,
        rectangular && cs.rectangular,
        className,
      )}
      fluid
      hideArrow
      items={renderDropdownItems()}
      onChange={handleResultSelect}
      open={!!shouldOpen}
      trigger={renderSearchBox()}
      usePortal
      withinModal
      disableAutocomplete={true}
    />
  );
};

export default LiveSearchPopBox;
