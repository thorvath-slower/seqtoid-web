module Mutations
  # Shared by CreateBulkDownload / createAsyncBulkDownload (CZID-304). Reproduces
  # BulkDownloadsController#create: build the create params (mirroring the federation body),
  # validate the viewable objects, resolve them to pipeline/workflow run ids, create the
  # BulkDownload, and kick it off -- raising a GraphQL error on save/kickoff failure
  # (matching the federation's throw-on-error behavior). Returns the saved BulkDownload.
  module BulkDownloadCreating
    include BulkDownloadsHelper # validate_bulk_download_create_params, get_valid_pipeline_run_ids_for_samples
    # validate_bulk_download_create_params -> validate_num_objects calls get_app_config, which lives
    # in AppConfigHelper. Controllers auto-include all helpers; GraphQL mutations do not, so include
    # it explicitly or the resolver raises NoMethodError (undefined method `get_app_config`). Mirrors
    # the same fix already on BulkDownloadCgOverviewQuery (CZID-307). Fixes both CreateBulkDownload
    # and CreateAsyncBulkDownload, which include this concern.
    include AppConfigHelper

    def create_bulk_download(input)
      run_ids = input.workflow_run_ids_strings&.map { |id| id && id.to_i } || input.workflow_run_ids
      workflow = input.workflow || WorkflowRun::WORKFLOW[:short_read_mngs]

      create_params = {
        download_type: input.download_type,
        workflow: workflow,
        params: {
          download_format: { value: input.download_format },
          sample_ids: { value: run_ids },
          workflow: { value: workflow },
        },
        workflow_run_ids: run_ids,
      }

      pipeline_run_ids = []
      workflow_run_ids = []
      viewable_objects = validate_bulk_download_create_params(create_params, context[:current_user])
      if [WorkflowRun::WORKFLOW[:short_read_mngs], WorkflowRun::WORKFLOW[:long_read_mngs]].include?(workflow)
        pipeline_run_ids = get_valid_pipeline_run_ids_for_samples(viewable_objects)
      else
        workflow_run_ids = viewable_objects.active.pluck(:id)
      end

      bulk_download = BulkDownload.new(
        download_type: input.download_type,
        pipeline_run_ids: pipeline_run_ids,
        workflow_run_ids: workflow_run_ids,
        params: create_params[:params],
        status: BulkDownload::STATUS_WAITING,
        user_id: context[:current_user].id
      )

      unless bulk_download.save
        raise GraphQL::ExecutionError, BulkDownloadsHelper::KICKOFF_FAILURE_HUMAN_READABLE
      end

      begin
        bulk_download.kickoff
      rescue StandardError
        bulk_download.update(status: BulkDownload::STATUS_ERROR)
        raise GraphQL::ExecutionError, BulkDownloadsHelper::KICKOFF_FAILURE_HUMAN_READABLE
      end

      bulk_download
    end
  end
end
