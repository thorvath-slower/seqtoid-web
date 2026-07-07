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
      # Warden failure_app rewrites the body; assert status only.
      expect(response).to have_http_status(:unauthorized)
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
