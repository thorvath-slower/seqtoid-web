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

    # BulkDownloadsHelper validation (validate_bulk_download_create_params and the
    # validate_num_objects it calls) signals domain-validation failures with a bare
    # `raise "<message>"` -- a plain RuntimeError, not a GraphQL::ExecutionError. Under the
    # controller these surfaced as a rendered JSON error; in the ported mutations they were
    # unrescued and bubbled out of `resolve` as an uncaught 500 (#458, follow-up to the #451
    # port-gap fix). We convert only these known domain messages into a GraphQL error so they
    # come back in the response `errors` array; any other RuntimeError is re-raised untouched
    # so we do not mask unrelated failures.
    BULK_DOWNLOAD_DOMAIN_ERROR_MESSAGES = [
      BulkDownloadsHelper::SAMPLE_NO_PERMISSION_ERROR,
      BulkDownloadsHelper::WORKFLOW_RUN_NO_PERMISSION_ERROR,
      BulkDownloadsHelper::SAMPLE_STILL_RUNNING_ERROR,
      BulkDownloadsHelper::SAMPLE_FAILED_ERROR,
      BulkDownloadsHelper::APP_CONFIG_MAX_OBJECTS_NOT_SET,
      BulkDownloadsHelper::UNKNOWN_DOWNLOAD_TYPE,
      BulkDownloadsHelper::ADMIN_ONLY_DOWNLOAD_TYPE,
      BulkDownloadsHelper::COLLABORATOR_ONLY_DOWNLOAD_TYPE,
      BulkDownloadsHelper::UPLOADER_ONLY_DOWNLOAD_TYPE,
    ].freeze

    # MAX_OBJECTS_EXCEEDED is a `% max` template, so it has no fixed string to match on.
    BULK_DOWNLOAD_DOMAIN_ERROR_TEMPLATES = [
      BulkDownloadsHelper::MAX_OBJECTS_EXCEEDED_ERROR_TEMPLATE,
    ].freeze

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
      begin
        viewable_objects = validate_bulk_download_create_params(create_params, context[:current_user])
      rescue RuntimeError => e
        raise GraphQL::ExecutionError, e.message if bulk_download_domain_error?(e.message)

        raise
      end
      if [WorkflowRun::WORKFLOW[:short_read_mngs], WorkflowRun::WORKFLOW[:long_read_mngs]].include?(workflow)
        pipeline_run_ids = get_valid_pipeline_run_ids_for_samples(viewable_objects)
      else
        workflow_run_ids = viewable_objects.active.pluck(:id)
      end

      # BulkDownload#get_param_value reads params via `params.dig(key, "value")` with a
      # STRING "value" key, and params_checks (e.g. the consensus_genome download_format
      # guard) relies on it. The controller path feeds the model an ActionController::
      # Parameters#to_hash, whose keys are all strings, so those lookups resolve. Here we
      # build create_params with SYMBOL keys, so without stringifying, get_param_value
      # returns nil and CG (and any other type with a params_checks guard) fails to save
      # with KICKOFF_FAILURE_HUMAN_READABLE. Deep-stringify to match the controller.
      bulk_download = BulkDownload.new(
        download_type: input.download_type,
        pipeline_run_ids: pipeline_run_ids,
        workflow_run_ids: workflow_run_ids,
        params: create_params[:params].deep_stringify_keys,
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

    private

    # True when the RuntimeError message is one of the known BulkDownloadsHelper
    # domain-validation errors (fixed strings or the MAX_OBJECTS template). Keeps the
    # rescue targeted so only user-facing validation failures become GraphQL errors.
    def bulk_download_domain_error?(message)
      return true if BULK_DOWNLOAD_DOMAIN_ERROR_MESSAGES.include?(message)

      BULK_DOWNLOAD_DOMAIN_ERROR_TEMPLATES.any? do |template|
        pattern = Regexp.new("\\A#{Regexp.escape(template).gsub('%s', '.+')}\\z")
        pattern.match?(message)
      end
    end
  end
end
