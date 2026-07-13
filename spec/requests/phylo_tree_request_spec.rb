require 'rails_helper'

# Full-stack request specs for PhyloTreesController.
#
# PhyloTree access control is unusual (see the class comment in
# app/controllers/phylo_trees_controller.rb): index/show viewability is derived
# from the viewability of every pipeline_run in the tree, and the controller is
# wrapped in an assert_access / check_access guard. These specs exercise the
# real routing + power(:phylo_trees) chain and pin: the JSON index shape, the
# human-taxid guard, name validation, the scoped set_phylo_tree lookup, and the
# download not-found branch.
RSpec.describe "PhyloTree request", type: :request do
  create_users

  describe "GET /phylo_trees/index.json" do
    before { sign_in @joe }

    it "returns project/taxon/phyloTrees keys as JSON" do
      # A tree with no pipeline_runs is viewable by any user (the viewability
      # subquery is vacuously satisfied), so it appears in joe's index.
      tree = create(:phylo_tree, user: @joe, name: "Joe Tree")

      get "/phylo_trees/index", params: { format: "json" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("phyloTrees")
      ids = body["phyloTrees"].map { |t| t["id"] }
      expect(ids).to include(tree.id)
    end

    it "returns a forbidden message for a human taxid instead of running the query" do
      # 9606 is in HUMAN_TAX_IDS; the controller short-circuits to a forbidden
      # message payload (rendered with a 200) before touching the DB.
      get "/phylo_trees/index", params: { format: "json", taxId: 9606 }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("forbidden")
      expect(body["message"]).to match(/Human taxon ids/i)
    end
  end

  describe "GET /phylo_trees/validate_name" do
    before { sign_in @joe }

    it "reports a unique, sanitized name as valid" do
      get "/phylo_trees/validate_name", params: { format: "json", name: "brand new tree" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["valid"]).to be(true)
      expect(body["sanitizedName"]).to eq("brand new tree")
    end

    it "reports a duplicate name as invalid (uniqueness)" do
      create(:phylo_tree, user: @joe, name: "taken_name")

      get "/phylo_trees/validate_name", params: { format: "json", name: "taken_name" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["valid"]).to be(false)
    end
  end

  describe "GET /choose_taxon" do
    before { sign_in @joe }

    it "returns the taxon_search results as JSON" do
      # taxon_search hits Elasticsearch; stub it at the controller mixin so the
      # request exercises routing + auth + the JSON dump path without ES.
      results = [{ "taxid" => 570, "title" => "Klebsiella", "level" => "genus" }]
      allow_any_instance_of(PhyloTreesController)
        .to receive(:taxon_search).and_return(results)

      get "/choose_taxon", params: { query: "kleb", args: "genus,species" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(results)
    end
  end

  describe "GET /phylo_trees/:id/show" do
    before { sign_in @joe }

    it "raises RecordNotFound for a tree id that does not exist (scoped find)" do
      # set_phylo_tree uses phylo_trees_scope.find(id) => power(:phylo_trees),
      # so a missing/out-of-scope id raises RecordNotFound rather than leaking.
      expect do
        get "/phylo_trees/#{PhyloTree.maximum(:id).to_i + 1}/show"
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "GET /phylo_trees/:id/download" do
    before { sign_in @joe }

    it "returns 404 when the requested output file is missing on the tree" do
      tree = create(:phylo_tree, user: @joe, name: "Downloadable Tree")

      # No S3 file is set for the requested output column, so download falls to
      # the head :not_found branch (no send_file).
      get "/phylo_trees/#{tree.id}/download", params: { output: "newick" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
