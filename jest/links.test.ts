// CZID-586 (#586) frontend coverage wave 1. links.ts holds the navigation / download
// helpers used across the app (open in same vs new tab, CSV download, popup windows,
// CSRF form POST). It is self-contained and only touches DOM globals, so it is
// deterministic under jsdom. These tests cover both arms of the modifier-key branch,
// the CSV escaping/quoting branches, and the DOM side effects.
import {
  downloadFileFromCSV,
  downloadStringToFile,
  openUrl,
  openUrlInNewTab,
  openUrlInPopupWindow,
  postToUrlWithCSRF,
} from "../app/assets/src/components/utils/links";

describe("links.openUrl", () => {
  let openSpy: jest.SpyInstance;

  beforeEach(() => {
    openSpy = jest.spyOn(window, "open").mockImplementation(() => null);
  });
  afterEach(() => {
    openSpy.mockRestore();
  });

  it("opens in the same tab with no modifier event", () => {
    openUrl("https://example.com/a");
    expect(openSpy).toHaveBeenCalledWith("https://example.com/a", "_self");
  });

  it("opens in a new tab when the meta key is held", () => {
    openUrl("https://example.com/b", { metaKey: true, ctrlKey: false });
    expect(openSpy).toHaveBeenCalledWith(
      "https://example.com/b",
      "_blank",
      "noreferrer",
    );
  });

  it("opens in a new tab when the ctrl key is held", () => {
    openUrl("https://example.com/c", { metaKey: false, ctrlKey: true });
    expect(openSpy).toHaveBeenCalledWith(
      "https://example.com/c",
      "_blank",
      "noreferrer",
    );
  });

  it("opens in the same tab when an event has no modifiers", () => {
    openUrl("https://example.com/d", { metaKey: false, ctrlKey: false });
    expect(openSpy).toHaveBeenCalledWith("https://example.com/d", "_self");
  });
});

describe("links.openUrlInNewTab", () => {
  it("delegates to window.open with the noreferrer blank target", () => {
    const openSpy = jest.spyOn(window, "open").mockImplementation(() => null);
    openUrlInNewTab("https://example.com/new");
    expect(openSpy).toHaveBeenCalledWith(
      "https://example.com/new",
      "_blank",
      "noreferrer",
    );
    openSpy.mockRestore();
  });
});

describe("links.openUrlInPopupWindow", () => {
  it("centers the popup and forwards the sizing string", () => {
    const openSpy = jest.spyOn(window, "open").mockImplementation(() => null);
    openUrlInPopupWindow("https://example.com/popup", "myWin", 400, 300);
    expect(openSpy).toHaveBeenCalledTimes(1);
    const [url, name, features] = openSpy.mock.calls[0];
    expect(url).toBe("https://example.com/popup");
    expect(name).toBe("myWin");
    expect(features).toContain("width=400");
    expect(features).toContain("height=300");
    expect(features).toContain("menubar=no");
    openSpy.mockRestore();
  });
});

describe("links.downloadStringToFile", () => {
  it("creates an object URL for the blob and navigates to it", () => {
    // jsdom does not implement URL.createObjectURL, so install a stub to spy on.
    const createStub = jest.fn(() => "blob:fake-url");
    (URL as unknown as { createObjectURL: unknown }).createObjectURL =
      createStub;
    // Replace location so the assignment does not trigger a jsdom navigation error.
    const originalLocation = window.location;
    Object.defineProperty(window, "location", {
      value: { href: "" },
      writable: true,
      configurable: true,
    });

    downloadStringToFile("hello world");

    expect(createStub).toHaveBeenCalledTimes(1);
    expect(window.location.href).toBe("blob:fake-url");

    Object.defineProperty(window, "location", {
      value: originalLocation,
      writable: true,
      configurable: true,
    });
    delete (URL as unknown as { createObjectURL?: unknown }).createObjectURL;
  });
});

describe("links.downloadFileFromCSV", () => {
  let clickSpy: jest.SpyInstance;

  beforeEach(() => {
    // Anchor.click() would attempt navigation in jsdom; stub it out.
    clickSpy = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => undefined);
  });
  afterEach(() => {
    clickSpy.mockRestore();
  });

  it("builds a download anchor, clicks it, then removes it", () => {
    const appendSpy = jest.spyOn(document.body, "appendChild");
    const removeSpy = jest.spyOn(document.body, "removeChild");

    downloadFileFromCSV(
      [
        ["col1", "col2"],
        ["a", "b"],
      ],
      "myfile",
    );

    expect(clickSpy).toHaveBeenCalledTimes(1);
    const anchor = appendSpy.mock.calls[0][0] as HTMLAnchorElement;
    expect(anchor.getAttribute("download")).toBe("myfile.csv");
    expect(anchor.getAttribute("href")).toContain("data:text/csv");
    // The anchor is cleaned up after the click.
    expect(removeSpy).toHaveBeenCalledWith(anchor);

    appendSpy.mockRestore();
    removeSpy.mockRestore();
  });

  it("quotes cells containing commas and blanks out null cells", () => {
    const appendSpy = jest.spyOn(document.body, "appendChild");

    downloadFileFromCSV([["has,comma", null], null], "quoted");

    const anchor = appendSpy.mock.calls[0][0] as HTMLAnchorElement;
    const decoded = decodeURI(anchor.getAttribute("href") as string);
    // The comma-containing cell is wrapped in quotes; the null cell is empty.
    expect(decoded).toContain('"has,comma"');
    appendSpy.mockRestore();
  });

  it("strips newlines out of a cell value", () => {
    const appendSpy = jest.spyOn(document.body, "appendChild");

    downloadFileFromCSV([["line1\nline2"]], "nl");

    const anchor = appendSpy.mock.calls[0][0] as HTMLAnchorElement;
    const decoded = decodeURI(anchor.getAttribute("href") as string);
    expect(decoded).toContain("line1line2");
    appendSpy.mockRestore();
  });
});

describe("links.postToUrlWithCSRF", () => {
  let submitSpy: jest.SpyInstance;

  beforeEach(() => {
    // form.submit() is not implemented in jsdom; stub it.
    submitSpy = jest
      .spyOn(HTMLFormElement.prototype, "submit")
      .mockImplementation(() => undefined);
    // The function reads the CSRF token off a named meta tag.
    const meta = document.createElement("meta");
    meta.setAttribute("name", "csrf-token");
    (meta as HTMLMetaElement).content = "tok-123";
    document.body.appendChild(meta);
  });
  afterEach(() => {
    submitSpy.mockRestore();
    document.body.innerHTML = "";
  });

  it("builds a POST form with the CSRF token plus extra params and submits it", () => {
    const appendSpy = jest.spyOn(document.body, "appendChild");

    postToUrlWithCSRF("/do/thing", { foo: "bar" });

    const form = appendSpy.mock.calls
      .map(c => c[0])
      .find(el => (el as HTMLElement).tagName === "FORM") as HTMLFormElement;
    expect(form.getAttribute("method")).toBe("POST");
    expect(form.getAttribute("action")).toBe("/do/thing");

    const inputs = Array.from(form.querySelectorAll("input")).map(i => [
      i.getAttribute("name"),
      i.getAttribute("value"),
    ]);
    expect(inputs).toContainEqual(["authenticity_token", "tok-123"]);
    expect(inputs).toContainEqual(["foo", "bar"]);
    expect(submitSpy).toHaveBeenCalledTimes(1);

    appendSpy.mockRestore();
  });

  it("defaults params to an empty object when omitted", () => {
    postToUrlWithCSRF("/no/params");
    expect(submitSpy).toHaveBeenCalledTimes(1);
  });
});
