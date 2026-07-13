require "rails_helper"

# Request specs for AdminController (previously uncovered).
# The controller is gated by authenticate_user! (Warden) plus login_required
# and admin_required (both redirect to root_path). Non-admins are redirected;
# admins render the discovery view router.
# See app/controllers/admin_controller.rb.
RSpec.describe "Admin request", type: :request do
  create_users

  describe "GET /admin (index)" do
    it "requires authentication" do
      get "/admin"
      # This is an HTML controller: unauthenticated users are redirected to
      # login (302 Found) rather than receiving a 401 JSON body.
      expect(response).to have_http_status(:found)
    end

    it "redirects a signed-in non-admin to the root path" do
      sign_in @joe
      get "/admin"
      expect(response).to redirect_to(root_path)
    end

    it "renders for a signed-in admin" do
      sign_in @admin
      get "/admin"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/settings" do
    it "redirects a non-admin and renders for an admin" do
      sign_in @joe
      get "/admin/settings"
      expect(response).to redirect_to(root_path)

      sign_in @admin
      get "/admin/settings"
      expect(response).to have_http_status(:ok)
    end
  end
end
