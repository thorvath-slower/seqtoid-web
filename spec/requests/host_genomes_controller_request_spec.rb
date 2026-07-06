require 'rails_helper'

# Full-stack request specs for HostGenomesController.
#
# Focus: the admin-only gate (before_action :admin_required, except:
# [:index, :index_public]), the public unauthenticated endpoint
# (skip_before_action :authenticate_user! on :index_public), and the JSON
# create/update/destroy admin paths. See app/controllers/host_genomes_controller.rb.
RSpec.describe "HostGenomes request", type: :request do
  create_users

  describe "GET /host_genomes/index_public (public, no auth)" do
    it "is reachable without signing in and returns only public fields" do
      hg = create(:host_genome)

      get "/host_genomes/index_public"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      returned = body.find { |h| h["id"] == hg.id }
      expect(returned).not_to be_nil
      expect(returned.keys).to contain_exactly("id", "name", "showAsOption")
    end
  end

  describe "GET /host_genomes.json (index)" do
    it "requires authentication" do
      create(:host_genome)
      get "/host_genomes.json"
      # Warden failure_app renders {error: 'Unauthorized', code: 401} for JSON.
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include("Unauthorized")
    end

    it "returns the full host genome list for a signed-in user" do
      hg = create(:host_genome)
      sign_in @joe

      get "/host_genomes.json"

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |h| h["id"] }
      expect(ids).to include(hg.id)
    end
  end

  describe "POST /host_genomes.json (admin-only create)" do
    it "redirects a regular user to root_path (admin_required)" do
      sign_in @joe
      post "/host_genomes.json", params: { host_genome: { name: "New Host" } }
      expect(response).to redirect_to(root_path)
    end

    it "creates a host genome for an admin (HTML redirect)" do
      sign_in @admin

      # NOTE: the JSON create path renders :show, but host_genomes has no
      # show.json view (only show.html.erb), so we exercise the HTML path which
      # redirects to the created record. The DB-level side effect is the point.
      expect do
        post "/host_genomes", params: { host_genome: { name: "Admin Created Host" } }
      end.to change(HostGenome, :count).by(1)

      created = HostGenome.order(:id).last
      expect(created.name).to eq("Admin Created Host")
      expect(response).to redirect_to(host_genome_path(created))
    end

    it "re-renders new (200) with errors when the name is missing" do
      sign_in @admin

      expect do
        post "/host_genomes", params: { host_genome: { name: "" } }
      end.not_to change(HostGenome, :count)

      # invalid create renders :new (200) rather than redirecting
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PUT /host_genomes/:id (admin-only update)" do
    it "redirects a regular user to root_path" do
      hg = create(:host_genome)
      sign_in @joe

      put "/host_genomes/#{hg.id}", params: { host_genome: { name: "Renamed" } }

      expect(response).to redirect_to(root_path)
      expect(hg.reload.name).not_to eq("Renamed")
    end

    it "updates the record for an admin (HTML redirect)" do
      hg = create(:host_genome)
      sign_in @admin

      put "/host_genomes/#{hg.id}", params: { host_genome: { name: "Renamed By Admin" } }

      expect(hg.reload.name).to eq("Renamed By Admin")
      expect(response).to redirect_to(host_genome_path(hg))
    end
  end

  describe "DELETE /host_genomes/:id.json (admin-only destroy)" do
    it "redirects a regular user to root_path" do
      hg = create(:host_genome)
      sign_in @joe

      expect do
        delete "/host_genomes/#{hg.id}.json"
      end.not_to change(HostGenome, :count)

      expect(response).to redirect_to(root_path)
    end

    it "destroys the record for an admin" do
      hg = create(:host_genome)
      sign_in @admin

      expect do
        delete "/host_genomes/#{hg.id}.json"
      end.to change(HostGenome, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
