require 'rails_helper'

# Full-stack request specs for HomeController.
#
# HomeController hosts the app's public + authenticated "shell" endpoints:
# the landing page, the maintenance/404 pages, the account-request (sign_up)
# form, small JSON utilities (taxon_descriptions, feedback), and the
# admin-gated app-config endpoints. These run through the real routing + auth
# chain, so they pin the login_required / admin_required boundaries that a
# controller spec (which bypasses the middleware) can silently miss.
RSpec.describe "Home request", type: :request do
  create_users

  describe "GET / (landing, public)" do
    it "renders the public landing page for an anonymous visitor" do
      get "/"

      expect(response).to have_http_status(:ok)
      # Anonymous landing hides the app header and shows the marketing header.
      expect(response.body).to be_present
    end
  end

  describe "GET /home (index) redirects" do
    before { sign_in @joe }

    it "redirects to my_data when no project_id is given" do
      get "/home"
      expect(response).to redirect_to(my_data_path)
    end

    it "redirects to my_data for a project the user owns" do
      project = create(:project, users: [@joe])
      get "/home", params: { project_id: project.id }
      expect(response).to redirect_to(action: "my_data", project_id: project.id.to_s)
    end

    it "redirects to public for a public project the user does not own" do
      project = create(:project, users: [@admin], public_access: 1)
      get "/home", params: { project_id: project.id }
      expect(response).to redirect_to(action: "public", project_id: project.id.to_s)
    end
  end

  describe "GET /taxon_descriptions" do
    before { sign_in @joe }

    it "returns descriptions keyed by taxid for the requested list" do
      TaxonDescription.create!(
        taxid: 561,
        title: "Escherichia",
        summary: "A genus of bacteria.",
        wikipedia_id: "12345" # required by TaxonDescription; backs #wiki_url
      )

      get "/taxon_descriptions", params: { taxon_list: "561,562" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("561")
      expect(body["561"]).to include("title" => "Escherichia")
      # wiki_url is a computed method (not a column). It must be included in the
      # payload; previously `slice` dropped it (#294).
      expect(body["561"]).to include(
        "wiki_url" => "https://en.wikipedia.org/wiki/index.html?curid=12345"
      )
      # 562 has no description row, so it is simply absent (not an error).
      expect(body).not_to have_key("562")
    end
  end

  describe "POST /feedback" do
    before { sign_in @joe }

    it "returns an ok status payload" do
      post "/feedback"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("status" => "ok")
    end
  end

  describe "POST /sign_up (public account request)" do
    it "rejects a submission missing required fields with 406" do
      post "/sign_up", params: { signUp: { firstName: "Only" } }

      # sign_up returns :not_acceptable when any required field is missing,
      # before touching mailers/airtable.
      expect(response).to have_http_status(:not_acceptable)
    end
  end

  describe "admin-gated app config endpoints" do
    describe "GET /app_configs" do
      it "redirects a regular user to root_path (admin_required)" do
        sign_in @joe
        get "/app_configs"
        expect(response).to redirect_to(root_path)
      end

      it "returns the app configs as JSON for an admin" do
        sign_in @admin
        AppConfig.create!(key: "some_flag", value: "1")

        get "/app_configs"

        expect(response).to have_http_status(:ok)
        keys = JSON.parse(response.body).map { |c| c["key"] }
        expect(keys).to include("some_flag")
      end
    end

    describe "PUT /set_app_config" do
      it "redirects a regular user to root_path (admin_required)" do
        sign_in @joe
        put "/set_app_config", params: { key: "some_flag", value: "1" }
        expect(response).to redirect_to(root_path)
      end

      it "sets a config value for an admin" do
        sign_in @admin
        put "/set_app_config", params: { key: "some_flag", value: "yes" }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq("status" => "success")
        expect(AppConfig.find_by(key: "some_flag")&.value).to eq("yes")
      end
    end

    describe "PUT /workflow_version" do
      it "redirects a regular user to root_path (admin_required)" do
        sign_in @joe
        put "/workflow_version", params: { key: "short-read-mngs-version", value: "1.0.0" }
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "GET /maintenance" do
    before { sign_in @joe }

    it "redirects to root when the site is not in maintenance mode" do
      get "/maintenance"
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /user_profile_form" do
    before { sign_in @joe }

    it "renders successfully for a signed-in user" do
      get "/user_profile_form"
      expect(response).to have_http_status(:ok)
    end
  end
end
