require 'rails_helper'

# Full-stack request specs for BackgroundsController.
#
# Focus: the login gate (before_action :login_required), the admin-only gate on
# show/destroy (before_action :admin_required, except: [:create, :show_taxon_dist,
# :index]), and the create authorization branch that rejects sample_ids the
# current user cannot view. See app/controllers/backgrounds_controller.rb.
RSpec.describe "Backgrounds request", type: :request do
  create_users

  describe "GET /backgrounds.json (index, login required)" do
    it "redirects to root_path when not signed in (login_required)" do
      get "/backgrounds.json"
      expect(response).to redirect_to(root_path)
    end

    it "returns the viewable backgrounds for a signed-in user" do
      sign_in @joe
      bg = create(:background, user: @joe)

      get "/backgrounds.json"

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["backgrounds"].map { |b| b["id"] }
      expect(ids).to include(bg.id)
    end

    it "splits owned vs other backgrounds when categorizeBackgrounds is set" do
      sign_in @joe
      mine = create(:background, user: @joe)

      get "/backgrounds.json", params: { categorizeBackgrounds: true }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("owned_backgrounds")
      expect(body).to have_key("other_backgrounds")
      expect(body["owned_backgrounds"].map { |b| b["id"] }).to include(mine.id)
    end
  end

  describe "GET /backgrounds/:id (show, admin-only)" do
    it "redirects a regular user to root_path (admin_required)" do
      sign_in @joe
      bg = create(:background, user: @joe)

      get "/backgrounds/#{bg.id}"

      expect(response).to redirect_to(root_path)
    end

    it "renders for an admin" do
      sign_in @admin
      bg = create(:background, user: @admin)

      get "/backgrounds/#{bg.id}.json"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /backgrounds (create)" do
    before { sign_in @joe }

    it "rejects creation when a sample id is not viewable by the current user" do
      other_project = create(:project, users: [@admin])
      other_sample = create(:sample, project: other_project, user: @admin)

      expect do
        post "/backgrounds", params: { name: "Bad BG", sample_ids: [other_sample.id] }
      end.not_to change(Background, :count)

      body = JSON.parse(response.body)
      expect(body["message"]).to eq("You are not authorized to view all samples in the list.")
    end
  end

  describe "DELETE /backgrounds/:id (admin-only destroy)" do
    it "redirects a regular user to root_path" do
      sign_in @joe
      bg = create(:background, user: @joe)

      expect do
        delete "/backgrounds/#{bg.id}.json"
      end.not_to change(Background, :count)

      expect(response).to redirect_to(root_path)
    end

    it "destroys the background for an admin" do
      sign_in @admin
      bg = create(:background, user: @admin)

      expect do
        delete "/backgrounds/#{bg.id}.json"
      end.to change(Background, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
