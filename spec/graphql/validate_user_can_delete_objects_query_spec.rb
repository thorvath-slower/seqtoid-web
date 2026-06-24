require "rails_helper"

RSpec.describe GraphqlController, type: :request do
  create_users

  query = <<GQL
  query BulkDeleteModalQuery($selectedIds: [Int], $selectedIdsStrings: [String], $workflow: String!, $authenticityToken: String!) {
    ValidateUserCanDeleteObjects(input: {selectedIds: $selectedIds, selectedIdsStrings: $selectedIdsStrings, workflow: $workflow, authenticityToken: $authenticityToken}) {
      validIdsStrings
      invalidSampleNames
      error
    }
  }
GQL

  context "Joe" do
    before { sign_in @joe }

    it "returns valid id strings and invalid sample names" do
      project = create(:project, users: [@joe])
      invalid_sample = create(:sample, project: project, user: @joe, name: "Invalid Sample")
      allow(DeletionValidationService).to receive(:call).and_return(
        valid_ids: [101, 102],
        invalid_sample_ids: [invalid_sample.id],
        error: nil
      )

      post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
        query: query,
        variables: {
          selectedIds: [101, 102, invalid_sample.id],
          selectedIdsStrings: ["101", "102", invalid_sample.id.to_s],
          workflow: "short-read-mngs",
          authenticityToken: "token",
        },
      }.to_json

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")
      data = parsed.dig("data", "ValidateUserCanDeleteObjects")
      expect(data["validIdsStrings"]).to eq(["101", "102"])
      expect(data["invalidSampleNames"]).to eq(["Invalid Sample"])
      expect(data["error"]).to be_nil
    end

    it "surfaces a validation error" do
      allow(DeletionValidationService).to receive(:call).and_return(
        valid_ids: [],
        invalid_sample_ids: [],
        error: "Some validation error"
      )

      post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
        query: query,
        variables: {
          selectedIds: [1],
          selectedIdsStrings: ["1"],
          workflow: "short-read-mngs",
          authenticityToken: "token",
        },
      }.to_json

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")
      data = parsed.dig("data", "ValidateUserCanDeleteObjects")
      expect(data["error"]).to eq("Some validation error")
      expect(data["validIdsStrings"]).to eq([])
    end
  end
end
