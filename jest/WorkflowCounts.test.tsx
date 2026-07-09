// CZID-586 (#586) frontend coverage: WorkflowCounts renders per-project sample
// and per-workflow run counts in the discovery table, with a loading state when
// counts are missing.
import { render, screen } from "@testing-library/react";
import React from "react";
import { WorkflowCounts } from "~/components/common/TableRenderers/components/WorkflowCounts/WorkflowCounts";
import { WorkflowType } from "~/components/utils/workflows";

const projectId = 7;
const fullCounts = {
  [projectId]: {
    [WorkflowType.SHORT_READ_MNGS]: 3,
    [WorkflowType.CONSENSUS_GENOME]: 2,
    [WorkflowType.AMR]: 1,
  },
} as any;

describe("WorkflowCounts", () => {
  it("renders the sample count and per-workflow counts when all are present", () => {
    render(
      React.createElement(WorkflowCounts, {
        workflowRunsProjectAggregates: fullCounts,
        numberOfSamples: 5,
        projectId,
      }),
    );
    expect(screen.getByTestId("sample-counts").textContent).toBe("5 Samples");
    const analyses = screen.getByTestId("nmgs-cg-sample-counts").textContent;
    expect(analyses).toContain("3 mNGS");
    expect(analyses).toContain("2 CG");
    expect(analyses).toContain("1 AMR");
  });

  it("uses the singular 'Sample' for exactly one sample", () => {
    render(
      React.createElement(WorkflowCounts, {
        workflowRunsProjectAggregates: fullCounts,
        numberOfSamples: 1,
        projectId,
      }),
    );
    expect(screen.getByTestId("sample-counts").textContent).toBe("1 Sample");
  });

  it("renders the loading placeholder when counts are missing", () => {
    const { container } = render(
      React.createElement(WorkflowCounts, {
        workflowRunsProjectAggregates: undefined,
        numberOfSamples: 5,
        projectId,
      }),
    );
    // No count test ids render; a loading div takes their place.
    expect(screen.queryByTestId("sample-counts")).toBeNull();
    expect(container.querySelector("div")).toBeTruthy();
  });
});
