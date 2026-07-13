require "rails_helper"

# CZID-469: audit the ported bulk-download create path across workflow types.
# Unlike create_bulk_download_mutation_spec.rb, these examples do NOT stub
# validate_bulk_download_create_params, so the real BulkDownloadsHelper chain runs
# end to end (get_app_config, current_user.admin?, viewable-object resolution,
# collaborator/uploader guards). Kickoff is stubbed so no real job is submitted.
#
# The goal is to catch port-gap style raises (NoMethodError / uncaught RuntimeError)
# and the create-param shape mismatch between the REST controller and the GraphQL
# mutation for the sample-based (mNGS) workflows.
RSpec.describe GraphqlController, type: :request do
  create_users

  ASYNC_MUTATION_AUDIT = <<GQL.freeze
  mutation BulkDownloadModalMutation($input: mutationInput_CreateBulkDownload_input_Input) {
    createAsyncBulkDownload(input: $input) {
      id
    }
  }
GQL

  def cg_workflow_run
    project = create(:project, users: [@joe])
    sample = create(:sample, project: project, user: @joe)
    create(:workflow_run, sample: sample, user: @joe,
                          workflow: WorkflowRun::WORKFLOW[:consensus_genome],
                          status: WorkflowRun::STATUS[:succeeded], deprecated: false)
  end

  def amr_workflow_run
    project = create(:project, users: [@joe])
    sample = create(:sample, project: project, user: @joe)
    create(:workflow_run, sample: sample, user: @joe,
                          workflow: WorkflowRun::WORKFLOW[:amr],
                          status: WorkflowRun::STATUS[:succeeded], deprecated: false)
  end

  def post_async(input)
    post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
      query: ASYNC_MUTATION_AUDIT,
      variables: { input: input },
    }.to_json
    JSON.parse(response.body)
  end

  def error_messages(parsed)
    Array(parsed["errors"]).map { |e| e["message"] }.join(" | ")
  end

  before do
    sign_in @joe
    AppConfigHelper.set_app_config(AppConfig::MAX_OBJECTS_BULK_DOWNLOAD, "100")
    AppConfigHelper.set_app_config(AppConfig::MAX_SAMPLES_BULK_DOWNLOAD_ORIGINAL_FILES, "100")
    allow_any_instance_of(BulkDownload).to receive(:kickoff)
  end

  context "consensus-genome workflow (the real frontend GraphQL path)" do
    it "consensus_genome_intermediate_output_files creates with workflow run ids" do
      wr = cg_workflow_run
      parsed = post_async(
        downloadType: "consensus_genome_intermediate_output_files",
        workflow: "consensus-genome",
        workflowRunIdsStrings: [wr.id.to_s],
        authenticityToken: "t"
      )
      expect(parsed["errors"]).to(be_nil, "errors: #{error_messages(parsed)}")
      expect(BulkDownload.last.workflow_run_ids).to eq([wr.id])
    end

    # Regression for the symbol-vs-string params key bug: consensus_genome runs a
    # params_checks guard on download_format via get_param_value (which digs a STRING
    # "value" key). If create_params[:params] keeps symbol keys the guard sees nil and
    # the save fails with KICKOFF_FAILURE_HUMAN_READABLE. deep_stringify_keys fixes it.
    it "consensus_genome (separate files) creates and preserves the download_format param" do
      wr = cg_workflow_run
      parsed = post_async(
        downloadType: "consensus_genome",
        workflow: "consensus-genome",
        downloadFormat: "Separate Files",
        workflowRunIdsStrings: [wr.id.to_s],
        authenticityToken: "t"
      )
      expect(parsed["errors"]).to(be_nil, "errors: #{error_messages(parsed)}")
      bulk_download = BulkDownload.last
      expect(bulk_download.workflow_run_ids).to eq([wr.id])
      expect(bulk_download.get_param_value("download_format")).to eq("Separate Files")
    end
  end

  context "amr workflow (schema-reachable, not driven by the frontend)" do
    it "amr_results_bulk_download creates with workflow run ids" do
      wr = amr_workflow_run
      parsed = post_async(
        downloadType: "amr_results_bulk_download",
        workflow: "amr",
        workflowRunIdsStrings: [wr.id.to_s],
        authenticityToken: "t"
      )
      expect(parsed["errors"]).to(be_nil, "errors: #{error_messages(parsed)}")
      expect(BulkDownload.last.workflow_run_ids).to eq([wr.id])
    end
  end

  # These document the create-param shape mismatch for the sample-based (mNGS)
  # workflows: the mutation puts sample ids only under params[:sample_ids] and sets
  # workflow_run_ids at the top level, but validate_bulk_download_create_params reads
  # create_params[:sample_ids] / create_params[:workflow_run_ids] at the TOP level.
  # For a short-read-mngs create the ids are really SAMPLE ids, but validation looks
  # them up against current_power.workflow_runs, so a real sample id will fail the
  # permission check (WORKFLOW_RUN_NO_PERMISSION_ERROR) unless it coincidentally
  # matches a viewable workflow run.
  context "short-read-mngs workflow (schema-reachable, not driven by the frontend)" do
    it "sample-id create is validated against workflow_runs, not samples (documents the mismatch)" do
      project = create(:project, users: [@joe])
      sample = create(:sample, project: project, user: @joe,
                               pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED }])

      parsed = post_async(
        downloadType: "sample_taxon_report",
        workflow: "short-read-mngs",
        workflowRunIdsStrings: [sample.id.to_s],
        authenticityToken: "t"
      )

      # The sample id is looked up as a workflow-run id and comes back as a
      # permission failure instead of creating the download.
      expect(error_messages(parsed)).to match(/permission to access all of the selected workflow runs/)
    end
  end
end
