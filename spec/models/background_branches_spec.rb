require 'rails_helper'

# Coverage Wave 2 (branch): background_spec.rb covers validations/compute_stdev/
# viewable/scopes. This adds summarize_taxon's mass_normalized vs. non-normalized
# branches (pure computation), the rel_abundance all-present vs. containing-nil
# branch, top_for_sample, eligible_pipeline_runs, destroy, and the
# viewable no-viewable-runs (condition_a = "false") branch.
RSpec.describe Background, type: :model do
  before do
    @user = create(:user)
    @project = create(:project, users: [@user])
  end

  def taxon_result(mass: false)
    r = { tax_id: 1, count_type: "NT", tax_level: 1,
          sum_rpm: 10.0, sum_rpm2: 60.0, rpm_list: [1.0, 2.0],
          rel_abundance_list_mass_normalized: [0.1, 0.2] }
    if mass
      r[:sum_mass_norm_count] = 4.0
      r[:sum_mass_norm_count2] = 10.0
    end
    r
  end

  describe "#summarize_taxon" do
    it "computes mass-normalized mean/stdev for a mass_normalized background" do
      bg = build(:background, mass_normalized: true)
      out = bg.summarize_taxon(taxon_result(mass: true), 2, DateTime.now.in_time_zone)
      expect(out[:mean]).to eq(5.0)
      expect(out[:mean_mass_normalized]).to eq(2.0)
      expect(out[:stdev_mass_normalized]).to be_a(Float)
    end

    it "leaves mass-normalized fields nil for a non-normalized background" do
      bg = build(:background, mass_normalized: false)
      out = bg.summarize_taxon(taxon_result(mass: false), 2, DateTime.now.in_time_zone)
      expect(out[:mean_mass_normalized]).to be_nil
      expect(out[:stdev_mass_normalized]).to be_nil
    end

    it "pads rpm_list with zeroes up to n when all rel_abundance values are present" do
      bg = build(:background, mass_normalized: false)
      tr = taxon_result(mass: false)
      out = bg.summarize_taxon(tr, 4, DateTime.now.in_time_zone)
      # rpm_list becomes JSON only in the all-present branch.
      expect(out[:rpm_list]).to be_a(String)
      expect(JSON.parse(out[:rpm_list]).size).to eq(4)
    end

    it "does not JSON-encode rpm_list when a rel_abundance value is nil" do
      bg = build(:background, mass_normalized: false)
      tr = taxon_result(mass: false)
      tr[:rel_abundance_list_mass_normalized] = [0.1, nil]
      out = bg.summarize_taxon(tr, 2, DateTime.now.in_time_zone)
      # the `.all?` false branch leaves rpm_list as an Array.
      expect(out[:rpm_list]).to be_an(Array)
    end
  end

  describe ".top_for_sample" do
    it "unions public, user-owned, and host-default ready backgrounds" do
      sample = create(:sample, project: @project, user: @user)
      public_bg = create(:background, name: "Pub", public_access: true, ready: 1, user: nil)
      user_bg = create(:background, name: "Mine", public_access: false, ready: 1, user: @user)
      create(:background, name: "NotReady", public_access: true, ready: 0, user: nil)

      result = Background.top_for_sample(sample)
      expect(result).to include(public_bg, user_bg)
      expect(result.map(&:name)).not_to include("NotReady")
    end
  end

  describe ".eligible_pipeline_runs" do
    it "delegates to PipelineRun.top_completed_runs ordered by sample" do
      relation = double("relation")
      expect(PipelineRun).to receive(:top_completed_runs).and_return(relation)
      expect(relation).to receive(:order).with(:sample_id).and_return([])
      expect(Background.eligible_pipeline_runs).to eq([])
    end
  end

  describe "#destroy" do
    it "removes taxon summaries then destroys the record" do
      bg = create(:background, name: "Destroy BG", user: @user,
                               taxon_summaries_data: [{ tax_id: 1, count_type: "NT", tax_level: 1 }])
      expect(TaxonSummary.where(background_id: bg.id).count).to eq(1)
      bg.destroy
      expect(Background.exists?(bg.id)).to eq(false)
      expect(TaxonSummary.where(background_id: bg.id).count).to eq(0)
    end
  end

  describe ".viewable no-viewable-runs branch" do
    it "returns no private backgrounds for a user who can view nothing" do
      stranger = create(:user)
      private_bg = create(:background, name: "Hidden", user: @user, public_access: 0)
      # This user can view no pipeline runs -> condition_a becomes "false".
      expect(Background.viewable(stranger)).not_to include(private_bg)
    end
  end
end
