require 'rails_helper'

# Coverage Wave 2 (line+branch): phylo_tree_spec.rb is effectively empty. This
# covers the class scopes (in_progress, viewable/editable admin vs non-admin
# branches), s3_outputs, log_url (nil vs present), and the before_destroy
# cleanup_s3 hook.
RSpec.describe PhyloTree, type: :model do
  before do
    @user = create(:user)
    @admin = create(:admin)
    @project = create(:project, users: [@user])
  end

  describe ".in_progress" do
    it "returns only trees with STATUS_IN_PROGRESS" do
      in_prog = create(:phylo_tree, project: @project, user: @user, status: PhyloTree::STATUS_IN_PROGRESS)
      done = create(:phylo_tree, project: @project, user: @user, status: PhyloTree::STATUS_READY)
      expect(PhyloTree.in_progress).to include(in_prog)
      expect(PhyloTree.in_progress).not_to include(done)
    end
  end

  describe ".viewable" do
    it "returns all trees for an admin" do
      tree = create(:phylo_tree, project: @project, user: @user)
      expect(PhyloTree.viewable(@admin)).to include(tree)
    end

    it "restricts to trees whose pipeline runs the user can view" do
      # A tree with no pipeline runs is trivially viewable by any user.
      tree = create(:phylo_tree, project: @project, user: @user)
      expect(PhyloTree.viewable(@user)).to include(tree)
    end
  end

  describe ".editable" do
    it "returns all trees for an admin" do
      tree = create(:phylo_tree, project: @project, user: @user)
      expect(PhyloTree.editable(@admin)).to include(tree)
    end

    it "restricts a non-admin to trees on projects they can edit" do
      tree = create(:phylo_tree, project: @project, user: @user)
      other = create(:user)
      # `other` cannot edit @project, so the tree is not editable by them.
      expect(PhyloTree.editable(other)).not_to include(tree)
    end
  end

  describe "#s3_outputs" do
    it "returns the four expected output descriptors" do
      tree = create(:phylo_tree, project: @project, user: @user)
      outputs = tree.s3_outputs
      expect(outputs.keys).to contain_exactly("newick", "ncbi_metadata", "snp_annotations", "vcf")
      expect(outputs["newick"]["required"]).to eq(true)
      expect(outputs["vcf"]["remote"]).to eq(true)
    end
  end

  describe "#log_url" do
    it "returns nil without a job_log_id" do
      tree = create(:phylo_tree, project: @project, user: @user, job_log_id: nil)
      expect(tree.log_url).to be_nil
    end

    it "builds a cloudwatch URL when a job_log_id is present" do
      tree = create(:phylo_tree, project: @project, user: @user, job_log_id: "log-9")
      allow(AwsUtil).to receive(:get_cloudwatch_url).and_return("https://cw/log-9")
      expect(tree.log_url).to eq("https://cw/log-9")
    end
  end

  describe "before_destroy cleanup_s3" do
    it "clears the tree's S3 prefix on destroy" do
      tree = create(:phylo_tree, project: @project, user: @user)
      expect(S3Util).to receive(:delete_s3_prefix).with(a_string_including("phylo_trees/#{tree.id}"))
      tree.destroy
    end
  end
end
