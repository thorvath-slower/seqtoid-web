# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for Visualization. Targets the opposite
# branches of project_name (zero-sample "unknown"), db_search (nil-search
# else), viewable (admin all vs scoped), and each sort_visualizations arm.
describe Visualization, type: :model do
  let(:user) { create(:user) }
  let(:admin) { create(:admin) }

  describe "#project_name" do
    it "returns 'unknown' when there are no samples (the else branch)" do
      viz = create(:visualization, user_id: user.id, visualization_type: "heatmap", name: "Empty")
      expect(viz.project_name).to eq("unknown")
    end
  end

  describe ".db_search" do
    before do
      create(:visualization, user_id: user.id, visualization_type: "heatmap", name: "Alpha heatmap")
      create(:visualization, user_id: user.id, visualization_type: "tree", name: "Beta tree")
    end

    it "filters by LIKE when a search term is given (the truthy branch)" do
      results = Visualization.db_search("Alpha")
      expect(results.pluck(:name)).to eq(["Alpha heatmap"])
    end

    it "trims whitespace around the search term" do
      results = Visualization.db_search("  Alpha  ")
      expect(results.pluck(:name)).to eq(["Alpha heatmap"])
    end
  end

  describe ".viewable" do
    it "returns all for an admin user (the admin branch)" do
      create(:visualization, user_id: user.id, visualization_type: "heatmap", name: "V", public_access: 0)
      expect(Visualization.viewable(admin).count).to eq(Visualization.count)
    end

    it "returns public + own for a non-admin user (the else branch)" do
      other = create(:user)
      mine = create(:visualization, user_id: user.id, visualization_type: "heatmap", name: "Mine", public_access: 0)
      pub = create(:visualization, user_id: other.id, visualization_type: "heatmap", name: "Pub", public_access: 1)
      hidden = create(:visualization, user_id: other.id, visualization_type: "heatmap", name: "Hidden", public_access: 0)

      ids = Visualization.viewable(user).pluck(:id)
      expect(ids).to include(mine.id, pub.id)
      expect(ids).not_to include(hidden.id)
    end
  end

  describe ".sort_visualizations" do
    let!(:v1) { create(:visualization, user_id: user.id, visualization_type: "heatmap", name: "aaa") }
    let!(:v2) { create(:visualization, user_id: user.id, visualization_type: "heatmap", name: "bbb") }

    it "sorts by a name/updated_at column key (first arm)" do
      result = Visualization.sort_visualizations(Visualization.all, "visualization", "asc")
      expect(result.pluck(:name)).to eq(%w[aaa bbb])
    end

    it "sorts by samples_count (second arm)" do
      result = Visualization.sort_visualizations(Visualization.all, "samples_count", "desc")
      expect(result.map(&:id)).to match_array([v1.id, v2.id])
    end

    it "sorts by project (third arm)" do
      result = Visualization.sort_visualizations(Visualization.all, "project_name", "asc")
      expect(result.map(&:id)).to match_array([v1.id, v2.id])
    end

    it "returns visualizations unchanged for an unknown sort key (the else)" do
      result = Visualization.sort_visualizations(Visualization.all, "nonexistent", "asc")
      expect(result.map(&:id)).to match_array([v1.id, v2.id])
    end
  end
end
