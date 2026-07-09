// CZID-586 (#586) frontend coverage: SingleVersionTextHeader is the pipeline
// version header shown when only one pipeline version exists.
import { render, screen } from "@testing-library/react";
import React from "react";
import { SingleVersionTextHeader } from "~/components/common/PipelineVersionSelect/components/SingleVersionTextHeader/SingleVersionTextHeader";

describe("SingleVersionTextHeader", () => {
  it("renders the current pipeline string and version info", () => {
    render(
      React.createElement(SingleVersionTextHeader, {
        currentPipelineString: "Pipeline v8.3",
        versionInfoString: "| Last run 2 days ago",
      }),
    );
    expect(screen.getByTestId("pipeline-version-select").textContent).toBe(
      "Pipeline v8.3",
    );
    expect(screen.getByText("| Last run 2 days ago")).toBeTruthy();
  });
});
