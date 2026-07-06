require 'rails_helper'

# Full-stack request specs for VisualizationsController.
#
# These exercise the routing + auth chain (unlike the controller specs, which
# bypass routing) and — most importantly — assert the real authorization
# boundaries: a visualization is only viewable by its owner, a public
# visualization, or an admin (Visualization.viewable). See app/models/power.rb
# and app/models/visualization.rb#viewable.
RSpec.describe "Visualizations request", type: :request do
  create_users

  let(:build_visualization) do
    lambda do |owner:, public_access: 0, name: "Owned Heatmap"|
      project = create(:project, users: [owner])
      sample = create(:sample, project: project, user: owner)
      vis = create(
        :visualization,
        user_id: owner.id,
        visualization_type: "heatmap",
        name: name,
        public_access: public_access
      )
      vis.samples << sample
      vis
    end
  end

  describe "GET /visualizations.json (index)" do
    context "when not signed in" do
      it "returns 401 Not Authenticated for the JSON endpoint instead of leaking data" do
        get "/visualizations.json", params: { domain: "my_data" }
        # Full-stack: the Warden failure_app (config/initializers/auth0.rb) renders
        # {error: 'Unauthorized', code: 401} before the controller runs, so we get
        # a 401 JSON response rather than ApplicationController's {errors: ['Not
        # Authenticated']} (that branch is only hit in controller specs, which skip
        # the middleware). The point — a 401, no data leak — holds either way.
        expect(response).to have_http_status(:unauthorized)
        expect(response.media_type).to eq("application/json")
        expect(response.body).to include("Unauthorized")
      end
    end

    context "when signed in as a regular user" do
      before { sign_in @joe }

      it "returns only the current user's own visualizations for my_data" do
        mine = build_visualization.call(owner: @joe, name: "Joe Heatmap")
        _theirs = build_visualization.call(owner: @admin, name: "Admin Heatmap")

        get "/visualizations.json", params: { domain: "my_data" }

        expect(response).to have_http_status(:ok)
        ids = JSON.parse(response.body).map { |v| v["id"] }
        expect(ids).to include(mine.id)
        expect(ids).not_to include(_theirs.id)
      end

      it "does not return another user's private visualization in the public domain" do
        private_other = build_visualization.call(owner: @admin, public_access: 0, name: "Admin Private")

        get "/visualizations.json", params: { domain: "public" }

        expect(response).to have_http_status(:ok)
        ids = JSON.parse(response.body).map { |v| v["id"] }
        expect(ids).not_to include(private_other.id)
      end

      it "does return another user's public visualization in the public domain" do
        public_other = build_visualization.call(owner: @admin, public_access: 1, name: "Admin Public")

        get "/visualizations.json", params: { domain: "public" }

        expect(response).to have_http_status(:ok)
        ids = JSON.parse(response.body).map { |v| v["id"] }
        expect(ids).to include(public_other.id)
      end
    end
  end

  describe "GET /visualizations/:type/:id (show)" do
    before { sign_in @joe }

    it "raises RecordNotFound when the visualization belongs to another user (scoped by current_power)" do
      other = build_visualization.call(owner: @admin, public_access: 0)

      # #visualization uses current_power.visualizations.find(id) which raises for
      # objects the user cannot view. This is the correct, scoped behavior.
      expect do
        get "/visualizations/heatmap/#{other.id}"
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "PUT /visualizations/:id (update / rename)" do
    before { sign_in @joe }

    it "renames the current user's own visualization" do
      mine = build_visualization.call(owner: @joe, name: "Original Name")

      put "/visualizations/#{mine.id}", params: { name: "Renamed By Owner" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("Renamed By Owner")
      expect(mine.reload.name).to eq("Renamed By Owner")
    end

    # SECURITY / AUTHORIZATION BOUNDARY (see #294):
    # VisualizationsController#update calls the UNSCOPED `Visualization.find(id)`
    # rather than `current_power.visualizations.find(id)` (as #show does). That
    # means any authenticated user can rename ANY visualization by id — an IDOR.
    #
    # This example documents the CURRENT behavior so that a fix (scoping the
    # lookup) flips it. If it starts failing because the rename was rejected,
    # that is the bug being fixed — update the expectation then.
    it "currently ALLOWS a non-owner to rename another user's private visualization (IDOR — see #294)" do
      other_owner_vis = build_visualization.call(owner: @admin, public_access: 0, name: "Admin Private Viz")

      put "/visualizations/#{other_owner_vis.id}", params: { name: "Hijacked" }

      expect(response).to have_http_status(:ok)
      # Demonstrates the missing authorization check: the rename went through.
      expect(other_owner_vis.reload.name).to eq("Hijacked")
    end
  end
end
