// #586 (epic #462) coverage: stringUtil.pluralize drives grammatically-correct
// count messaging (irregular verbs + regular -s). Every branch arm is exercised.
import { pluralize } from "../app/assets/src/components/utils/stringUtil";

describe("pluralize", () => {
  it("returns the singular form untouched when count is exactly 1", () => {
    expect(pluralize("sample", 1)).toBe("sample");
    expect(pluralize("has", 1)).toBe("has");
  });

  it("maps irregular words to their plural form for count != 1", () => {
    expect(pluralize("has", 2)).toBe("have");
    expect(pluralize("was", 0)).toBe("were");
    expect(pluralize("is", 3)).toBe("are");
    expect(pluralize("it", 5)).toBe("they");
    expect(pluralize("does", 2)).toBe("do");
  });

  it("appends an s for regular words when count != 1", () => {
    expect(pluralize("sample", 2)).toBe("samples");
    expect(pluralize("project", 0)).toBe("projects");
  });
});
