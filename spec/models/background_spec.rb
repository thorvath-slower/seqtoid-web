require 'rails_helper'

RSpec.describe Background, type: :model do
  # Helper: create a project with two finalized pipeline runs and return their ids.
  def two_pipeline_run_ids(project:, total_ercc_reads: nil)
    s1 = create(:sample, project: project,
                         pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED }])
    s2 = create(:sample, project: project,
                         pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED }])
    ids = [s1.first_pipeline_run.id, s2.first_pipeline_run.id]
    unless total_ercc_reads.nil?
      PipelineRun.where(id: ids).update_all(total_ercc_reads: total_ercc_reads)
    end
    ids
  end

  before do
    @user = create(:user)
    @project = create(:project, users: [@user])
  end

  context "validations" do
    it "is valid with a name and at least 2 pipeline runs" do
      bg = build(:background, name: "Valid BG", pipeline_run_ids: two_pipeline_run_ids(project: @project))
      expect(bg).to be_valid
    end

    it "requires a name" do
      bg = build(:background, name: nil, pipeline_run_ids: two_pipeline_run_ids(project: @project))
      expect(bg).not_to be_valid
      expect(bg.errors[:name]).to be_present
    end

    it "enforces case-insensitive uniqueness of name" do
      create(:background, name: "Dup BG", pipeline_run_ids: two_pipeline_run_ids(project: @project))
      dup = build(:background, name: "dup bg", pipeline_run_ids: two_pipeline_run_ids(project: @project))
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to be_present
    end

    it "requires at least 2 pipeline runs" do
      s1 = create(:sample, project: @project,
                           pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED }])
      bg = build(:background, name: "Too Small", pipeline_run_ids: [s1.first_pipeline_run.id])
      expect(bg).not_to be_valid
      expect(bg.errors[:base].join).to match(/at least 2 pipeline runs/)
    end

    it "rejects a mass_normalized background whose runs have no erccs" do
      bg = build(:background, name: "No ERCC MN",
                              mass_normalized: true,
                              pipeline_run_ids: two_pipeline_run_ids(project: @project, total_ercc_reads: 0))
      expect(bg).not_to be_valid
      expect(bg.errors[:base].join).to match(/mass normalized/)
    end

    it "allows a mass_normalized background when runs have erccs" do
      bg = build(:background, name: "MN With ERCC",
                              mass_normalized: true,
                              pipeline_run_ids: two_pipeline_run_ids(project: @project, total_ercc_reads: 100))
      expect(bg).to be_valid
    end
  end

  context "#mass_normalized?" do
    it "reflects the mass_normalized attribute" do
      bg = build(:background, mass_normalized: false)
      expect(bg.mass_normalized?).to be_falsey
    end
  end

  context "#compute_stdev" do
    it "computes the sample standard deviation" do
      bg = Background.new
      # values 2 and 4: sum=6, sum2=20, n=2 => variance=(20-18)/1=2 => sqrt(2)
      expect(bg.compute_stdev(6.0, 20.0, 2)).to be_within(1e-9).of(Math.sqrt(2))
    end

    it "clamps tiny negative variance from rounding to zero" do
      bg = Background.new
      # sum=4, sum2=8, n=2 => variance=(8-8)/1=0
      expect(bg.compute_stdev(4.0, 8.0, 2)).to eq(0.0)
    end
  end

  context ".created_by_idseq scope" do
    it "returns public backgrounds with no user" do
      idseq_bg = create(:background, name: "IDseq BG", user: nil, public_access: 1,
                                     pipeline_run_ids: two_pipeline_run_ids(project: @project))
      user_bg = create(:background, name: "User BG", user: @user, public_access: 1,
                                    pipeline_run_ids: two_pipeline_run_ids(project: @project))
      result = Background.created_by_idseq
      expect(result).to include(idseq_bg)
      expect(result).not_to include(user_bg)
    end
  end

  context ".viewable" do
    it "returns all backgrounds for an admin" do
      admin = create(:admin)
      bg = create(:background, name: "Admin View BG", user: @user, public_access: 0,
                               pipeline_run_ids: two_pipeline_run_ids(project: @project))
      expect(Background.viewable(admin)).to include(bg)
    end

    it "returns public backgrounds to a non-owning user" do
      other_user = create(:user)
      public_bg = create(:background, name: "Public View BG", user: @user, public_access: 1,
                                      pipeline_run_ids: two_pipeline_run_ids(project: @project))
      expect(Background.viewable(other_user)).to include(public_bg)
    end

    it "hides a private background from a user who cannot see its pipeline runs" do
      other_user = create(:user)
      private_bg = create(:background, name: "Private View BG", user: @user, public_access: 0,
                                       pipeline_run_ids: two_pipeline_run_ids(project: @project))
      expect(Background.viewable(other_user)).not_to include(private_bg)
    end

    it "shows a user a private background built from pipeline runs they can view" do
      private_bg = create(:background, name: "Own Private BG", user: @user, public_access: 0,
                                       pipeline_run_ids: two_pipeline_run_ids(project: @project))
      expect(Background.viewable(@user)).to include(private_bg)
    end
  end

  context "#alignment_config_names" do
    it "returns the distinct alignment config names of its pipeline runs" do
      config = create(:alignment_config, name: "2099-01-01")
      s1 = create(:sample, project: @project,
                           pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED, alignment_config: config }])
      s2 = create(:sample, project: @project,
                           pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED, alignment_config: config }])
      bg = create(:background, name: "Config BG", user: @user,
                               pipeline_run_ids: [s1.first_pipeline_run.id, s2.first_pipeline_run.id])
      expect(bg.alignment_config_names).to include("2099-01-01")
    end
  end

  context "#as_json" do
    it "includes alignment_config_names" do
      bg = create(:background, name: "JSON BG", user: @user,
                               pipeline_run_ids: two_pipeline_run_ids(project: @project))
      expect(bg.as_json).to have_key("alignment_config_names")
    end
  end
end
