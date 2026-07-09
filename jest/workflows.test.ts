// CZID-462 (#586) coverage: app/assets/src/components/utils/workflows.ts
import {
  getShorthandFromWorkflow,
  getWorkflowTypeFromLabel,
  isMngsWorkflow,
  WORKFLOW_TABS,
  workflowIsWorkflowRunEntity,
  WORKFLOWS,
  WorkflowType,
} from "../app/assets/src/components/utils/workflows";

describe("workflows.ts", () => {
  describe("workflowIsWorkflowRunEntity", () => {
    it("is true for WorkflowRuns-backed workflows", () => {
      expect(workflowIsWorkflowRunEntity(WorkflowType.AMR)).toBe(true);
      expect(workflowIsWorkflowRunEntity(WorkflowType.CONSENSUS_GENOME)).toBe(
        true,
      );
      expect(workflowIsWorkflowRunEntity(WorkflowType.BENCHMARK)).toBe(true);
    });
    it("is false for Samples-backed workflows", () => {
      expect(workflowIsWorkflowRunEntity(WorkflowType.SHORT_READ_MNGS)).toBe(
        false,
      );
      expect(workflowIsWorkflowRunEntity(WorkflowType.LONG_READ_MNGS)).toBe(
        false,
      );
    });
  });

  describe("getShorthandFromWorkflow", () => {
    it("returns the configured shorthand", () => {
      expect(getShorthandFromWorkflow(WorkflowType.SHORT_READ_MNGS)).toBe(
        "mNGS",
      );
      expect(getShorthandFromWorkflow(WorkflowType.CONSENSUS_GENOME)).toBe(
        "CG",
      );
      expect(getShorthandFromWorkflow(WorkflowType.AMR)).toBe("AMR");
    });
  });

  describe("isMngsWorkflow", () => {
    it("is true for short and long read mNGS", () => {
      expect(isMngsWorkflow(WorkflowType.SHORT_READ_MNGS)).toBe(true);
      expect(isMngsWorkflow(WorkflowType.LONG_READ_MNGS)).toBe(true);
    });
    it("is false for non-mNGS workflows", () => {
      expect(isMngsWorkflow(WorkflowType.AMR)).toBe(false);
      expect(isMngsWorkflow(WorkflowType.CONSENSUS_GENOME)).toBe(false);
    });
  });

  describe("getWorkflowTypeFromLabel", () => {
    it("maps a direct label to its workflow type", () => {
      expect(getWorkflowTypeFromLabel("Consensus Genome")).toBe(
        WorkflowType.CONSENSUS_GENOME,
      );
      expect(getWorkflowTypeFromLabel("Metagenomic")).toBe(
        WorkflowType.SHORT_READ_MNGS,
      );
    });
    it("normalizes the deprecated/simplified labels to Metagenomic", () => {
      expect(
        getWorkflowTypeFromLabel("Antimicrobial Resistance (Deprecated)"),
      ).toBe(WorkflowType.SHORT_READ_MNGS);
      expect(getWorkflowTypeFromLabel("Metagenomics - Simplified")).toBe(
        WorkflowType.SHORT_READ_MNGS,
      );
    });
  });

  describe("static config objects", () => {
    it("exposes WORKFLOW_TABS keyed by shorthand, valued by label", () => {
      expect(WORKFLOW_TABS.SHORT_READ_MNGS).toBe(
        WORKFLOWS[WorkflowType.SHORT_READ_MNGS].label,
      );
    });
    it("marks the deprecated AMR entity as null", () => {
      expect(WORKFLOWS[WorkflowType.AMR_DEPRECATED].entity).toBeNull();
    });
  });
});
