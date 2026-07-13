// CZID-462 (#586) coverage: app/assets/src/components/utils/stringUtil.ts
import { pluralize } from "../app/assets/src/components/utils/stringUtil";

describe("stringUtil.ts pluralize", () => {
  it("returns the singular string unchanged when count is 1", () => {
    expect(pluralize("sample", 1)).toBe("sample");
    expect(pluralize("is", 1)).toBe("is");
  });

  it("uses the irregular map for known words", () => {
    expect(pluralize("has", 2)).toBe("have");
    expect(pluralize("was", 0)).toBe("were");
    expect(pluralize("is", 3)).toBe("are");
    expect(pluralize("it", 2)).toBe("they");
    expect(pluralize("does", 5)).toBe("do");
  });

  it("appends an s for regular words", () => {
    expect(pluralize("sample", 2)).toBe("samples");
    expect(pluralize("project", 0)).toBe("projects");
  });
});
