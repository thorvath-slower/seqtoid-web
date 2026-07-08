// #586 (epic #462) coverage: workflows.ts is the central workflow-type config and
// the label<->type mapping used everywhere in discovery/sample views. The
// label-to-type resolver has a legacy-alias branch worth pinning. Pure.
import {
  WORKFLOWS,
  WORKFLOW_ENTITIES,
  WORKFLOW_TABS,
  WorkflowType,
  getShorthandFromWorkflow,
  getWorkflowTypeFromLabel,
  isMngsWorkflow,
  workflowIsWorkflowRunEntity,
} from "../app/assets/src/components/utils/workflows";

describe("workflowIsWorkflowRunEntity", () => {
  it("is true for WorkflowRun-backed workflows (AMR, CG, benchmark)", () => {
    expect(workflowIsWorkflowRunEntity(WorkflowType.AMR)).toBe(true);
    expect(workflowIsWorkflowRunEntity(WorkflowType.CONSENSUS_GENOME)).toBe(
      true,
    );
  });

  it("is false for Sample-backed mNGS workflows", () => {
    expect(workflowIsWorkflowRunEntity(WorkflowType.SHORT_READ_MNGS)).toBe(
      false,
    );
    expect(WORKFLOWS[WorkflowType.SHORT_READ_MNGS].entity).toBe(
      WORKFLOW_ENTITIES.SAMPLES,
    );
  });
});

describe("getShorthandFromWorkflow", () => {
  it("returns the configured shorthand", () => {
    expect(getShorthandFromWorkflow(WorkflowType.CONSENSUS_GENOME)).toBe("CG");
    expect(getShorthandFromWorkflow(WorkflowType.AMR)).toBe("AMR");
  });
});

describe("isMngsWorkflow", () => {
  it("is true for short- and long-read mNGS", () => {
    expect(isMngsWorkflow(WorkflowType.SHORT_READ_MNGS)).toBe(true);
    expect(isMngsWorkflow(WorkflowType.LONG_READ_MNGS)).toBe(true);
  });

  it("is false for non-mNGS workflows", () => {
    expect(isMngsWorkflow(WorkflowType.AMR)).toBe(false);
    expect(isMngsWorkflow(WorkflowType.CONSENSUS_GENOME)).toBe(false);
  });
});

describe("getWorkflowTypeFromLabel", () => {
  it("resolves a canonical label to its workflow type", () => {
    expect(getWorkflowTypeFromLabel("Consensus Genome")).toBe(
      WorkflowType.CONSENSUS_GENOME,
    );
    expect(getWorkflowTypeFromLabel("Metagenomic")).toBe(
      WorkflowType.SHORT_READ_MNGS,
    );
  });

  it("collapses legacy mNGS aliases onto short-read mNGS", () => {
    expect(getWorkflowTypeFromLabel("Metagenomics - Simplified")).toBe(
      WorkflowType.SHORT_READ_MNGS,
    );
    expect(
      getWorkflowTypeFromLabel("Antimicrobial Resistance (Deprecated)"),
    ).toBe(WorkflowType.SHORT_READ_MNGS);
  });
});

describe("WORKFLOW_TABS", () => {
  it("maps shorthand keys to workflow labels", () => {
    expect(WORKFLOW_TABS.SHORT_READ_MNGS).toBe("Metagenomic");
    expect(WORKFLOW_TABS.CONSENSUS_GENOME).toBe("Consensus Genome");
  });
});
