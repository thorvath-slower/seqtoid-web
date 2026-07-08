// CZID-586 (#586) frontend coverage wave 1. UrlQueryParser is the query-string
// (de)serializer that drives deep-linkable SampleView / heatmap / discovery filters.
// Pure logic over query-string + lodash, so it is cheap deterministic coverage. These
// tests hit every convertValue type arm (incl. the unsupported-type warn branch), the
// object stringify empty/non-empty branches, and the has()/miss update branches.
import UrlQueryParser from "../app/assets/src/components/utils/UrlQueryParser";

describe("UrlQueryParser.parse", () => {
  it("passes through untyped params as raw strings", () => {
    const parser = new UrlQueryParser({});
    expect(parser.parse("?a=1&b=hello")).toEqual({ a: "1", b: "hello" });
  });

  it("coerces typed params to their declared types", () => {
    const parser = new UrlQueryParser({
      workflowRunId: "number",
      view: "string",
      selectedOptions: "object",
      persist: "boolean",
    } as $TSFixMe);
    const parsed = parser.parse(
      `?workflowRunId=42&view=table&selectedOptions=${encodeURIComponent(
        '{"background":9}',
      )}&persist=true`,
    );
    expect(parsed.workflowRunId).toBe(42);
    expect(parsed.view).toBe("table");
    expect(parsed.selectedOptions).toEqual({ background: 9 });
    expect(parsed.persist).toBe(true);
  });

  it("leaves a typed key untouched when it is absent from the query", () => {
    const parser = new UrlQueryParser({ workflowRunId: "number" } as $TSFixMe);
    expect(parser.parse("?other=x")).toEqual({ other: "x" });
  });
});

describe("UrlQueryParser.convertValue", () => {
  const parser = new UrlQueryParser({});

  it("parses object json", () => {
    expect(parser.convertValue('{"x":1}', "object")).toEqual({ x: 1 });
  });

  it("treats only the literal 'true' as boolean true", () => {
    expect(parser.convertValue("true", "boolean")).toBe(true);
    expect(parser.convertValue("false", "boolean")).toBe(false);
    expect(parser.convertValue("anything", "boolean")).toBe(false);
  });

  it("converts numbers", () => {
    expect(parser.convertValue("3.14", "number")).toBe(3.14);
  });

  it("returns strings unchanged", () => {
    expect(parser.convertValue("plain", "string")).toBe("plain");
  });

  it("warns and returns the raw value for an unsupported type", () => {
    const warnSpy = jest
      .spyOn(console, "warn")
      .mockImplementation(() => undefined);
    // @ts-expect-error deliberately passing an unsupported type to hit the default arm
    expect(parser.convertValue("v", "date")).toBe("v");
    expect(warnSpy).toHaveBeenCalled();
    warnSpy.mockRestore();
  });
});

describe("UrlQueryParser.stringify", () => {
  it("stringifies typed object values to JSON", () => {
    const parser = new UrlQueryParser({
      selectedOptions: "object",
    } as $TSFixMe);
    const out = parser.stringify({ selectedOptions: { background: 5 } });
    expect(decodeURIComponent(out)).toContain(
      'selectedOptions={"background":5}',
    );
  });

  it("drops empty object values (stringifyValue returns undefined)", () => {
    const parser = new UrlQueryParser({
      selectedOptions: "object",
    } as $TSFixMe);
    expect(parser.stringify({ selectedOptions: {} })).toBe("");
  });

  it("omits falsy values entirely", () => {
    const parser = new UrlQueryParser({} as $TSFixMe);
    expect(parser.stringify({ a: "", b: 0, c: "keep" })).toBe("c=keep");
  });

  it("passes untyped values straight through", () => {
    const parser = new UrlQueryParser({} as $TSFixMe);
    expect(parser.stringify({ view: "table" })).toBe("view=table");
  });
});

describe("UrlQueryParser.stringifyValue", () => {
  const parser = new UrlQueryParser({});

  it("returns non-object typed values as-is", () => {
    expect(parser.stringifyValue("raw" as $TSFixMe, "string")).toBe("raw");
  });

  it("returns undefined for an empty object", () => {
    expect(parser.stringifyValue({}, "object")).toBeUndefined();
  });
});

describe("UrlQueryParser.updateQueryStringParameter", () => {
  const parser = new UrlQueryParser({});

  it("updates an existing key", () => {
    const updated = parser.updateQueryStringParameter(
      "?view=table",
      "view",
      "tree",
    );
    expect(updated.view).toBe("tree");
  });

  it("leaves the params unchanged when the key is absent", () => {
    const updated = parser.updateQueryStringParameter(
      "?view=table",
      "missing",
      "x",
    );
    expect(updated).not.toHaveProperty("missing");
    expect(updated.view).toBe("table");
  });
});
