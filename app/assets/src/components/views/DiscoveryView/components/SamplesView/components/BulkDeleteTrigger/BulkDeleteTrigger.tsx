import { compact, filter, get, isEmpty, pullAll } from "lodash/fp";
import React, { useContext } from "react";
import { UserContext } from "~/components/common/UserContext";
import {
  getShorthandFromWorkflow,
  WorkflowType,
  WORKFLOW_ENTITIES,
} from "~/components/utils/workflows";
import { ObjectType } from "~/interface/samplesView";
import cs from "../../samples_view.scss";
import ToolbarButtonIcon from "../ToolbarButtonIcon/ToolbarButtonIcon";

interface BulkDeleteTriggerProps {
  onClick(): void;
  selectedObjects: ObjectType[];
  workflow: WorkflowType;
  workflowEntity: string;
  popupPosition?: "top left" | "top center";
}

const BulkDeleteTrigger = ({
  onClick,
  selectedObjects,
  workflow,
  workflowEntity,
  popupPosition,
}: BulkDeleteTriggerProps) => {
  const { userId } = useContext(UserContext) ?? {};

  // Matches the backend Sample::STALLED_UPLOAD_FINALIZATION_DELAY. An orphaned "created" upload
  // shell (no successful upload, no finalized error) becomes deletable once it is older than this,
  // mirroring Sample.orphaned_created_uploads so the UI stops blocking what the API will allow.
  const STALLED_UPLOAD_MS = 3 * 60 * 60 * 1000;

  // True for a sample that never progressed past "created": no finalized/running pipeline run and
  // no terminal workflow-run status, and old enough to be considered stalled. The backend
  // re-validates via orphaned_created_uploads, so this only governs whether the trigger is enabled.
  const isOrphanedCreatedUpload = (object: ObjectType): boolean => {
    const finalized = get(["sample", "pipelineRunFinalized"], object) === 1;
    const pipelineRunStatus = get(["sample", "pipelineRunStatus"], object);
    const runStatus = get(["status"], object);
    const hasProgressed =
      finalized ||
      !isEmpty(pipelineRunStatus) ||
      (!isEmpty(runStatus) && runStatus !== "created");
    if (hasProgressed) return false;

    const createdAt = get(["createdAt"], object);
    if (!createdAt) return false;
    const createdMs = new Date(createdAt).getTime();
    if (Number.isNaN(createdMs)) return false;
    return Date.now() - createdMs > STALLED_UPLOAD_MS;
  };

  const isAtLeastOneObjectValidForDeletion = () => {
    // selected samples uploaded by current user
    const filteredSamples = filter(obj => {
      const uploadedBy = obj.sample?.userId;
      return uploadedBy === userId;
    }, selectedObjects);

    // if user didn't upload any of the selected samples,
    // we can return false without checking if any of them completed,
    // since the user can't delete these anyway
    if (isEmpty(filteredSamples)) return false;

    // Allow deletion if a sample failed to upload (finalized upload error set by the backend).
    const uploadErrors = compact(
      filteredSamples.map(object => get(["sample", "uploadError"], object)),
    );
    if (!isEmpty(uploadErrors)) {
      return true;
    }

    // Also allow deletion of orphaned/stalled "created" upload shells. A stalled upload has a nil
    // upload_error, so it is not caught above; enable the owner to clear it from the UI once it is
    // old enough (the backend orphaned_created_uploads path authoritatively confirms deletion).
    if (filteredSamples.some(isOrphanedCreatedUpload)) {
      return true;
    }

    // if user uploaded something, check if any of the ones they uploaded completed
    if (workflowEntity === WORKFLOW_ENTITIES.WORKFLOW_RUNS) {
      const runStatuses = filteredSamples.map(object =>
        get(["status"], object),
      );
      return !isEmpty(pullAll(["running", "created"], runStatuses));
    }

    const statuses = filteredSamples.map(object =>
      get(["sample", "pipelineRunFinalized"], object),
    );

    return statuses.includes(1);
  };

  let disabled = false;
  let disabledMessage = "";
  let shouldInvertTooltip = true;
  let primaryText = `Delete ${getShorthandFromWorkflow(workflow)} Run`;

  // disabled because no samples selected in table
  if (selectedObjects?.length === 0) {
    disabled = true;
    disabledMessage = "Select at least 1 sample";
    // disabled because all selected samples cannot be deleted by this user at this time
  } else if (!isAtLeastOneObjectValidForDeletion()) {
    disabled = true;
    shouldInvertTooltip = false;
    primaryText = "";
    disabledMessage =
      "The Selected Samples can’t be deleted because they were all run by another user or are still being processed.";
  }

  return (
    <ToolbarButtonIcon
      className={cs.action}
      icon="trashCan"
      disabled={disabled}
      popupSubtitle={disabledMessage}
      popupText={primaryText}
      onClick={onClick}
      inverted={shouldInvertTooltip}
      testId="bulk-delete-trigger"
      popupPosition={popupPosition}
    />
  );
};

export { BulkDeleteTrigger };
