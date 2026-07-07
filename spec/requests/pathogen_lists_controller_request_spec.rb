require "rails_helper"

# Request specs for PathogenListsController#show (previously uncovered).
# The action skips authenticate_user!, so it is reachable anonymously.
# See app/controllers/pathogen_lists_controller.rb.
RSpec.describe "PathogenLists request", type: :request do
  create_users

  describe "GET /pathogen_list (public, no auth)" do
    it "renders the discovery view router without signing in" do
      get "/pathogen_list"
      expect(response).to have_http_status(:ok)
    end

    it "renders for a versioned path as well" do
      get "/pathogen_list/1.0.0"
      expect(response).to have_http_status(:ok)
    end
  end
end
