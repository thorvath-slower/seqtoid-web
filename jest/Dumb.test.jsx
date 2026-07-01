import React from "react";
import { render } from "@testing-library/react";

import Dumb from "./Dumb";

// CZID-381: migrated off enzyme (+ enzyme-adapter-react-16, which has no React 17/18 adapter) to
// React Testing Library. enzyme pulled a modern cheerio → undici → parse5-parser-stream chain that
// jest 26 could not load under React 18; RTL renders natively against jsdom with no such chain.
describe("Dumb", () => {
  it("renders text1 and text2 when both are present", () => {
    const { container } = render(<Dumb text1="test-1" text2="test-2" />);

    expect(container.textContent).toContain("Text 1 is: test-1");
    expect(container.textContent).toContain("Text 2 is: test-2");
  });

  it("omits a line when its text is missing", () => {
    const { container } = render(<Dumb text1="only-1" />);

    expect(container.textContent).toContain("Text 1 is: only-1");
    expect(container.textContent).not.toContain("Text 2 is:");
  });
});
