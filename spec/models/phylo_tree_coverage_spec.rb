require 'rails_helper'

# Supplementary coverage for PhyloTree model (Coverage Wave 4b). The stock
# phylo_tree_spec.rb is only a pending stub, so this covers scopes, viewability,
# validations, s3 output mapping and log url.
RSpec.describe PhyloTree, type: :model do
  create_users

  let(:project) { create(:project, users: [@joe]) }

  describe "validations" do
    it "rejects an out-of-range tax_level" do
      tree = build(:phylo_tree, project: project, tax_level: 99)
      expect(tree).not_to be_valid
      expect(tree.errors[:tax_level]).to be_present
    end

    it "rejects an out-of-range status" do
      tree = build(:phylo_tree, project: project, status: 42)
      expect(tree).not_to be_valid
      expect(tree.errors[:status]).to be_present
    end

    it "requires a taxid" do
      tree = build(:phylo_tree, project: project, taxid: nil)
      expect(tree).not_to be_valid
      expect(tree.errors[:taxid]).to be_present
    end
  end

  describe ".in_progress" do
    it "returns only trees in the in-progress status" do
      running = create(:phylo_tree, project: project, status: PhyloTree::STATUS_IN_PROGRESS)
      create(:phylo_tree, project: project, status: PhyloTree::STATUS_READY)
      expect(PhyloTree.in_progress).to contain_exactly(running)
    end
  end

  describe ".editable" do
    it "returns all trees for an admin" do
      tree = create(:phylo_tree, project: project)
      expect(PhyloTree.editable(@admin)).to include(tree)
      expect(PhyloTree.editable(@admin).count).to eq(PhyloTree.count)
    end
  end

  describe ".viewable" do
    it "returns all trees for an admin" do
      tree = create(:phylo_tree, project: project)
      expect(PhyloTree.viewable(@admin)).to include(tree)
      expect(PhyloTree.viewable(@admin).count).to eq(PhyloTree.count)
    end
  end

  describe ".users_by_tree_id" do
    it "indexes creating users by phylo tree id" do
      tree = create(:phylo_tree, project: project, user: @joe)
      result = PhyloTree.users_by_tree_id
      expect(result[tree.id]["name"]).to eq(@joe.name)
    end
  end

  describe "#s3_outputs" do
    it "maps output names to versioned s3 paths" do
      tree = create(:phylo_tree, project: project, dag_version: "1.0")
      outputs = tree.s3_outputs
      expect(outputs["newick"]["s3_path"]).to include("phylo_trees/#{tree.id}/1.0/phylo_tree.newick")
      expect(outputs["newick"]["required"]).to eq(true)
      expect(outputs["snp_annotations"]["remote"]).to eq(true)
    end
  end

  describe "#log_url" do
    it "returns nil when there is no job_log_id" do
      tree = create(:phylo_tree, project: project, job_log_id: nil)
      expect(tree.log_url).to be_nil
    end

    it "builds a cloudwatch url when a job_log_id is present" do
      tree = create(:phylo_tree, project: project, job_log_id: "job-123")
      expect(AwsUtil).to receive(:get_cloudwatch_url).with("/aws/batch/job", "job-123").and_return("https://cw.example/job-123")
      expect(tree.log_url).to eq("https://cw.example/job-123")
    end
  end
end
