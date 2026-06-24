require "rails_helper"

RSpec.describe GraphqlController, type: :request do
  create_users

  query = <<GQL
  query BulkDownloadModalQuery($workflowRunIdsStrings: [String], $includeMetadata: Boolean!, $downloadType: String!, $workflow: String!, $authenticityToken: String!) {
    BulkDownloadCGOverview(input: {workflowRunIdsStrings: $workflowRunIdsStrings, includeMetadata: $includeMetadata, downloadType: $downloadType, workflow: $workflow, authenticityToken: $authenticityToken}) {
      cgOverviewRows
    }
  }
GQL

  context "Joe" do
    before { sign_in @joe }

    it "returns the CG overview rows for viewable workflow runs" do
      rows = [["Sample Name", "Coverage Depth"], ["sampleA", "100"]]
      viewable = double("viewable_objects")
      allow(viewable).to receive(:active).and_return(double(pluck: [11, 22]))
      allow_any_instance_of(Types::QueryType)
        .to receive(:validate_bulk_download_create_params).and_return(viewable)
      allow(BulkDownloadsHelper).to receive(:generate_cg_overview_data).and_return(rows)

      post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
        query: query,
        variables: {
          workflowRunIdsStrings: ["11", "22"],
          includeMetadata: false,
          downloadType: "consensus_genome_intermediate_output_files",
          workflow: "consensus-genome",
          authenticityToken: "t",
        },
      }.to_json

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")
      data = parsed.dig("data", "BulkDownloadCGOverview")
      expect(data["cgOverviewRows"]).to eq(rows)
    end
  end
end
