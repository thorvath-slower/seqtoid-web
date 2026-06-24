require "rails_helper"

# CZID-304: native Rails GraphQL ports of the federation createAsyncBulkDownload /
# CreateBulkDownload mutations. Both reproduce BulkDownloadsController#create via the shared
# BulkDownloadCreating helper. The ECS kickoff side effect is stubbed so the spec never
# submits a real download job; the create-param validation is stubbed to the test's run.
RSpec.describe GraphqlController, type: :request do
  create_users

  ASYNC_MUTATION = <<GQL
  mutation BulkDownloadModalMutation($input: mutationInput_CreateBulkDownload_input_Input) {
    createAsyncBulkDownload(input: $input) {
      id
    }
  }
GQL

  CREATE_MUTATION = <<GQL
  mutation($input: mutationInput_CreateBulkDownload_input_Input) {
    CreateBulkDownload(input: $input)
  }
GQL

  def cg_workflow_run
    project = create(:project, users: [@joe])
    sample = create(:sample, project: project, user: @joe)
    create(:workflow_run, sample: sample, user: @joe,
                          workflow: WorkflowRun::WORKFLOW[:consensus_genome],
                          status: WorkflowRun::STATUS[:succeeded], deprecated: false)
  end

  context "Joe" do
    before { sign_in @joe }

    it "createAsyncBulkDownload creates a bulk download + returns its id" do
      wr = cg_workflow_run
      allow_any_instance_of(Mutations::CreateAsyncBulkDownload)
        .to receive(:validate_bulk_download_create_params).and_return(WorkflowRun.where(id: [wr.id]))
      allow_any_instance_of(BulkDownload).to receive(:kickoff)

      post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
        query: ASYNC_MUTATION,
        variables: { input: {
          downloadType: "consensus_genome_intermediate_output_files",
          workflow: "consensus_genome",
          downloadFormat: "Separate Files",
          workflowRunIdsStrings: [wr.id.to_s],
          authenticityToken: "t",
        } },
      }.to_json

      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      bulk_download = BulkDownload.last
      expect(parsed.dig("data", "createAsyncBulkDownload", "id")).to eq(bulk_download.id.to_s)
      expect(bulk_download.workflow_run_ids).to eq([wr.id])
      expect(bulk_download.status).to eq(BulkDownload::STATUS_WAITING)
    end

    it "CreateBulkDownload returns the created bulk download as JSON" do
      wr = cg_workflow_run
      allow_any_instance_of(Mutations::CreateBulkDownload)
        .to receive(:validate_bulk_download_create_params).and_return(WorkflowRun.where(id: [wr.id]))
      allow_any_instance_of(BulkDownload).to receive(:kickoff)

      post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
        query: CREATE_MUTATION,
        variables: { input: {
          downloadType: "consensus_genome_intermediate_output_files",
          workflow: "consensus_genome",
          downloadFormat: "Separate Files",
          workflowRunIdsStrings: [wr.id.to_s],
          authenticityToken: "t",
        } },
      }.to_json

      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")
      json = parsed.dig("data", "CreateBulkDownload")
      expect(json["id"]).to eq(BulkDownload.last.id)
      expect(json["download_type"]).to eq("consensus_genome_intermediate_output_files")
    end
  end
end
