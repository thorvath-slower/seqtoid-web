require 'rails_helper'

# Full-stack request specs for the NON-index/update actions of
# VisualizationsController (save, shorten_url, heatmap_metrics, samples_taxons,
# and the visualization#show redirect dispatch).
#
# NOTE: the index/update authorization boundaries (including the pinned
# update IDOR characterization, see #294) are already covered in
# spec/requests/visualization_request_spec.rb. These specs deliberately cover
# the OTHER actions and do not duplicate that suite.
RSpec.describe "Visualization feature request", type: :request do
  create_users

  describe "unauthenticated access" do
    it "returns 401 JSON for heatmap_metrics instead of leaking config" do
      get "/visualizations/heatmap_metrics.json"

      # The Warden failure_app (config/initializers/auth0.rb) renders a 401 JSON
      # before the controller runs. We pin: a 401, no data leak.
      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/json")
      expect(response.body).to include("Unauthorized")
    end
  end

  describe "GET /visualizations/heatmap_metrics.json" do
    before { sign_in @joe }

    it "returns the short-read mNGS heatmap metric list" do
      get "/visualizations/heatmap_metrics.json"

      expect(response).to have_http_status(:ok)
      expected = WorkflowRun::WORKFLOW_METRICS[WorkflowRun::WORKFLOW[:short_read_mngs]]
      expect(JSON.parse(response.body)).to eq(JSON.parse(expected.to_json))
    end
  end

  describe "GET /visualizations/samples_taxons.json" do
    before { sign_in @joe }

    it "returns an empty object when there are no samples for the heatmap" do
      # No sampleIds param and no id => samples_for_heatmap is blank, so the
      # action returns {} without hitting the (expensive) taxon computation.
      get "/visualizations/samples_taxons.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end
  end

  describe "POST /visualizations/shorten_url" do
    before { sign_in @joe }

    it "returns a unique_key for a shortened url" do
      post "/visualizations/shorten_url", params: { url: "https://czid.org/visualizations/heatmap/1" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("success")
      expect(body["unique_key"]).to be_present
    end
  end

  describe "POST /visualizations/:type/save" do
    before { sign_in @joe }

    let(:sample) do
      project = create(:project, users: [@joe])
      create(:sample, project: project, user: @joe)
    end

    it "creates a new visualization owned by the current user" do
      expect do
        post "/visualizations/heatmap/save", params: {
          type: "heatmap",
          data: { sampleIds: [sample.id], foo: "bar" },
        }
      end.to change(Visualization, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("success")
      expect(body["type"]).to eq("heatmap")
      expect(body["sample_ids"]).to eq([sample.id])

      vis = Visualization.find(body["id"])
      expect(vis.user_id).to eq(@joe.id)
      expect(vis.visualization_type).to eq("heatmap")
    end

    # CHARACTERIZATION of the #save "overwrite the most recent existing viz"
    # branch (see #294). The controller only reuses an existing visualization
    # when `v.sample_ids.to_set == sample_ids.to_set`, but over a real HTTP
    # request `sample_ids` arrives as an array of *strings* (["12"]) while
    # `v.sample_ids` is an array of *integers* ([12]), so the Set comparison
    # never matches and each save at the request layer creates a NEW record.
    #
    # This pins the CURRENT behavior. If a fix coerces the ids (making the
    # second save overwrite in place), this example will flip — update it then.
    it "currently creates a second record on re-save because param sample_ids are strings (see #294)" do
      post "/visualizations/heatmap/save", params: {
        type: "heatmap",
        data: { sampleIds: [sample.id], version: 1 },
      }
      first_id = JSON.parse(response.body)["id"]

      expect do
        post "/visualizations/heatmap/save", params: {
          type: "heatmap",
          data: { sampleIds: [sample.id], version: 2 },
        }
      end.to change(Visualization, :count).by(1)

      expect(JSON.parse(response.body)["id"]).not_to eq(first_id)
    end
  end

  describe "GET /visualizations/:type/:id (visualization#show redirect dispatch)" do
    before { sign_in @joe }

    it "redirects a phylo_tree_ng visualization to its tree page" do
      vis = create(
        :visualization,
        user_id: @joe.id,
        visualization_type: "phylo_tree_ng",
        name: "My NG Tree",
        data: { "treeNgId" => 42 }
      )

      get "/visualizations/phylo_tree_ng/#{vis.id}"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/phylo_tree_ngs/42")
    end

    it "redirects a phylo_tree visualization to the legacy phylo_trees index" do
      vis = create(
        :visualization,
        user_id: @joe.id,
        visualization_type: "phylo_tree",
        name: "My Legacy Tree",
        data: { "someKey" => "someVal" }
      )

      get "/visualizations/phylo_tree/#{vis.id}"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/phylo_trees/index")
    end

    it "raises RecordNotFound for a visualization the user cannot view (scoped by current_power)" do
      other = create(
        :visualization,
        user_id: @admin.id,
        visualization_type: "phylo_tree_ng",
        name: "Admin NG Tree",
        public_access: 0,
        data: { "treeNgId" => 7 }
      )

      expect do
        get "/visualizations/phylo_tree_ng/#{other.id}"
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
