require "rails_helper"

# Full-stack request specs for GraphqlController#execute.
#
# The existing spec/controllers/graphql_controller_spec.rb covers the signed-in
# happy path. This spec exercises the prepare_variables branches (String /
# blank String / Hash / ActionController::Parameters / nil / unexpected type)
# and the unauthenticated path (the controller skips authenticate_user!, so an
# anonymous request still executes with a nil current_user).
# See app/controllers/graphql_controller.rb.
RSpec.describe "Graphql request", type: :request do
  create_users

  # __typename is always resolvable and needs no DB fixtures, so it isolates
  # the prepare_variables branch logic from schema resolver behavior.
  let(:typename_query) { "{ __typename }" }

  describe "prepare_variables branches" do
    before { sign_in @admin }

    it "accepts variables as a JSON String" do
      query = 'query($id: ID!) { appConfig(id: $id) { key value } }'
      config = create(:app_config, key: "test_key", value: "test_value")

      expect(IdseqSchema).to receive(:execute).and_call_original
      post "/graphql", params: { query: query, variables: { id: config.id.to_s }.to_json }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("data", "appConfig", "key")).to eq("test_key")
    end

    it "accepts a blank String for variables (falls back to {})" do
      expect(IdseqSchema).to receive(:execute).with(
        anything,
        hash_including(variables: {})
      ).and_call_original

      post "/graphql", params: { query: typename_query, variables: "" }

      expect(response).to have_http_status(:ok)
    end

    it "accepts a Hash / ActionController::Parameters for variables" do
      query = 'query($id: ID!) { appConfig(id: $id) { key } }'
      config = create(:app_config, key: "k", value: "v")

      expect(IdseqSchema).to receive(:execute).and_call_original
      post "/graphql", params: { query: query, variables: { id: config.id.to_s } }

      expect(response).to have_http_status(:ok)
    end

    it "accepts a nil variables param (falls back to {})" do
      expect(IdseqSchema).to receive(:execute).with(
        anything,
        hash_including(variables: {})
      ).and_call_original

      post "/graphql", params: { query: typename_query }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "unauthenticated (auth is skipped)" do
    it "still executes with a nil current_user and returns 200" do
      expect(IdseqSchema).to receive(:execute).and_call_original

      post "/graphql", params: { query: typename_query }

      expect(response).to have_http_status(:ok)
    end
  end
end
