require "rails_helper"

# Regression for #451 / #452 / #458: the ported bulk-download mutations
# (createAsyncBulkDownload / CreateBulkDownload) must resolve the Rails helpers
# their REAL validation chain invokes. Unlike create_bulk_download_mutation_spec.rb,
# these examples do NOT stub `validate_bulk_download_create_params`, so the real
# BulkDownloadsHelper#validate_num_objects runs, which makes two bare helper calls
# that GraphQL mutations don't auto-resolve the way controllers do:
#   - get_app_config           (GAP 1 -- AppConfigHelper; fires on every create)
#   - current_user.admin?      (GAP 2 -- only over the object limit)
# Before the fix both raised `NoMethodError` on the mutation instance (a user-facing 500).
RSpec.describe GraphqlController, type: :request do
  create_users

  ASYNC_MUTATION_PG = <<GQL.freeze
  mutation BulkDownloadModalMutation($input: mutationInput_CreateBulkDownload_input_Input) {
    createAsyncBulkDownload(input: $input) {
      id
    }
  }
GQL

  def cg_workflow_run_pg
    project = create(:project, users: [@joe])
    sample = create(:sample, project: project, user: @joe)
    create(:workflow_run, sample: sample, user: @joe,
                          workflow: WorkflowRun::WORKFLOW[:consensus_genome],
                          status: WorkflowRun::STATUS[:succeeded], deprecated: false)
  end

  def post_async(wr)
    post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
      query: ASYNC_MUTATION_PG,
      variables: { input: {
        downloadType: "consensus_genome_intermediate_output_files",
        workflow: "consensus_genome",
        downloadFormat: "Separate Files",
        workflowRunIdsStrings: [wr.id.to_s],
        authenticityToken: "t",
      } },
    }.to_json
    JSON.parse(response.body)
  end

  def error_messages(parsed)
    Array(parsed["errors"]).map { |e| e["message"] }.join(" | ")
  end

  context "as non-admin Joe, exercising the real validation chain (no stub)" do
    before { sign_in @joe }

    it "GAP 1: createAsyncBulkDownload runs validate_num_objects -> get_app_config without NoMethodError" do
      wr = cg_workflow_run_pg
      # Under the limit (1 <= 100), so validate_num_objects reaches get_app_config
      # but short-circuits before current_user.admin? -- isolates GAP 1.
      AppConfigHelper.set_app_config(AppConfig::MAX_OBJECTS_BULK_DOWNLOAD, "100")
      allow_any_instance_of(BulkDownload).to receive(:kickoff)

      parsed = post_async(wr)

      # The port-gap crash must be gone...
      expect(error_messages(parsed)).not_to match(/undefined method .?get_app_config/)
      # ...and the create should succeed end-to-end.
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")
      expect(parsed.dig("data", "createAsyncBulkDownload", "id")).to eq(BulkDownload.last.id.to_s)
    end

    it "GAP 2 / #458: over the object limit comes back as a GraphQL error, not an uncaught RuntimeError 500" do
      wr = cg_workflow_run_pg
      # 1 object > 0 allowed -> validate_num_objects evaluates `current_user.admin?` (line 128)
      # then raises MAX_OBJECTS_EXCEEDED at :129.
      AppConfigHelper.set_app_config(AppConfig::MAX_OBJECTS_BULK_DOWNLOAD, "0")

      # #451 (GAP 2) closed the current_user port gap so the code reaches the domain guard.
      # #458 additionally requires that guard's bare RuntimeError be surfaced as a GraphQL
      # error in the response `errors` array -- NOT bubble out of resolve as a 500. So the
      # request must NOT raise, and the domain message must land in errors.
      parsed = nil
      expect { parsed = post_async(wr) }.not_to raise_error

      expect(error_messages(parsed)).to match(/No more than 0 objects allowed/)
      expect(parsed.dig("data", "createAsyncBulkDownload")).to be_nil
      # No stray bulk download should have been persisted on the validation failure.
      expect(BulkDownload.count).to eq(0)
    end
  end
end
