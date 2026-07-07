require "rails_helper"

# Request specs for SampleTypesController#index (previously uncovered).
# See app/controllers/sample_types_controller.rb.
RSpec.describe "SampleTypes request", type: :request do
  create_users

  describe "GET /sample_types.json" do
    it "requires authentication" do
      get "/sample_types.json"
      # Warden failure_app rewrites the body; assert status only.
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns all sample types as JSON for a signed-in user" do
      sign_in @joe
      st = create(:sample_type, name: "Serum", group: "Systemic Inflammation")

      get "/sample_types.json"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.map { |x| x["id"] }).to include(st.id)
    end
  end
end
