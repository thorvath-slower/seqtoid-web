require 'rails_helper'
require_relative '../../test/test_helpers/location_test_helper'

# Full-stack request specs for LocationsController.
#
# Focus: the token-auth external_search endpoint (empty-query short circuit +
# a mocked geosearch happy path) and the access-controlled sample_locations
# JSON endpoint. See app/controllers/locations_controller.rb.
RSpec.describe "Locations request", type: :request do
  create_users

  describe "GET /locations/external_search" do
    before { sign_in @joe }

    it "returns an empty array when the query is blank (no external call)" do
      get "/locations/external_search", params: { query: "" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("[]")
    end

    it "returns formatted geosearch results for a matching query" do
      allow(Location).to receive(:geo_search_request_base).and_return([true, LocationTestHelper::API_GEOSEARCH_RESPONSE])

      get "/locations/external_search", params: { query: "UCSF" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(JSON.dump(LocationTestHelper::FORMATTED_GEOSEARCH_RESPONSE))
    end

    it "returns 500 with the failure shape when geosearch raises" do
      allow(Location).to receive(:geo_search_request_base).and_raise(StandardError.new("boom"))

      get "/locations/external_search", params: { query: "UCSF" }

      expect(response).to have_http_status(:internal_server_error)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("failed")
      expect(body["message"]).to eq(LocationsController::GEOSEARCH_ERR_MSG)
    end
  end

  describe "GET /locations/sample_locations.json (access controlled)" do
    before { sign_in @joe }

    it "returns a JSON hash for the user's my_data domain" do
      project = create(:project, users: [@joe])
      create(:sample, project: project, user: @joe)

      get "/locations/sample_locations.json", params: { domain: "my_data" }

      expect(response).to have_http_status(:ok)
      # Samples without collection_location_v2 metadata simply yield an empty map;
      # the important thing is the endpoint runs the access-controlled query and
      # renders JSON rather than leaking or erroring.
      expect(JSON.parse(response.body)).to eq({})
    end
  end
end
