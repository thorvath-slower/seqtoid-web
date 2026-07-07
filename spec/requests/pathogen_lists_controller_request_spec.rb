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

    # The route is `get 'pathogen_list(/:version)'`. The optional :version
    # segment uses Rails' default constraint, which stops at a dot, so a
    # dotted semantic version like "1.0.0" does not match this route (it
    # raises ActionController::RoutingError). A non-dotted version segment
    # is what the route actually accepts.
    it "renders for a (non-dotted) versioned path as well" do
      get "/pathogen_list/v1"
      expect(response).to have_http_status(:ok)
    end
  end
end
