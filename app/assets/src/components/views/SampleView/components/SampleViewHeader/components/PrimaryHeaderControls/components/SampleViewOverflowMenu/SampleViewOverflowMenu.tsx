import React from "react";
import { isNotNullish } from "~/components/utils/typeUtils";
import { WORKFLOWS, WorkflowType } from "~/components/utils/workflows";
import {
  FINALIZED_SAMPLE_UPLOAD_ERRORS,
  SampleUploadErrors,
} from "~/components/views/DiscoveryView/components/SamplesView/components/CollectionModal/constants";
import { ReportMetadata } from "~/interface/reportMetaData";
import Sample, { WorkflowRun } from "~/interface/sample";
import { CurrentTabSample } from "~/interface/sampleView";
import { PipelineRun } from "~/interface/shared";
import { OverflowMenu } from "./components/OverflowMenu";
import { SampleViewOverflowMenuConfig } from "./workflowTypeConfig";

interface SampleViewOverflowMenuProps {
  className: string;
  currentRun: WorkflowRun | PipelineRun;
  currentTab: CurrentTabSample;
  onDeleteRunSuccess: () => void;
  reportMetadata: ReportMetadata;
  sample: Sample;
  workflow: WorkflowType;
}

export const SampleViewOverflowMenu = ({
  className,
  currentRun,
  currentTab,
  onDeleteRunSuccess,
  reportMetadata,
  sample,
  workflow,
}: SampleViewOverflowMenuProps) => {
  const { deleteId, readyToDelete, isVisible, isShortReadMngs } =
    SampleViewOverflowMenuConfig[workflow]({
      currentRun,
      reportMetadata,
      sample,
      currentTab,
    });
  if (!isVisible) return <></>;
  const workflowRuns = sample?.workflow_runs?.filter(isNotNullish) || [];
  const pipelineRuns = sample?.pipeline_runs?.filter(isNotNullish) || [];
  const redirectOnSuccess =
    sample && [...pipelineRuns, ...workflowRuns].length === 1;
  const runFinalized =
    currentRun?.run_finalized ||
    FINALIZED_SAMPLE_UPLOAD_ERRORS.includes(
      sample?.upload_error as SampleUploadErrors,
    );
  // Self-service recovery (CZID-676 Phase C). mNGS uses the sample-scoped retry/re-run
  // endpoints; CG/AMR use the workflow-run-scoped re-run. supportNote pre-populates the
  // support popup with this run's context for the UCSF team.
  const isMngs = [
    WorkflowType.SHORT_READ_MNGS,
    WorkflowType.LONG_READ_MNGS,
  ].includes(workflow);
  const supportNote = sample
    ? `Sample "${sample.name}" (id ${sample.id}) -- ${WORKFLOWS[workflow]?.label} run ${
        currentRun?.id ?? ""
      } needs help (processing issue).`
    : undefined;
  return (
    <OverflowMenu
      className={className}
      deleteId={deleteId}
      isShortReadMngs={isShortReadMngs}
      onDeleteRunSuccess={onDeleteRunSuccess}
      readyToDelete={readyToDelete}
      redirectOnSuccess={redirectOnSuccess}
      runFinalized={runFinalized}
      sampleUserId={sample?.user_id}
      workflowShorthand={WORKFLOWS[workflow].shorthand}
      workflowLabel={WORKFLOWS[workflow]?.label}
      sampleId={sample?.id}
      workflowRunId={currentRun?.id}
      isMngs={isMngs}
      supportNote={supportNote}
    />
  );
};
