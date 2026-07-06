require 'rails_helper'

RSpec.describe PersistedBackground, type: :model do
  before do
    @user = create(:user)
    @project = create(:project, users: [@user])

    sample_one = create(:sample, project: @project,
                                 pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED }])
    sample_two = create(:sample, project: @project,
                                 pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED }])
    @public_bg = create(:background, user: @user, name: "Public BG", public_access: 1, pipeline_run_ids: [
                          sample_one.first_pipeline_run.id,
                          sample_two.first_pipeline_run.id,
                        ])
  end

  context "associations" do
    it "belongs to user, project, and optionally background" do
      pb = create(:persisted_background, user_id: @user.id, project_id: @project.id, background_id: @public_bg.id)
      expect(pb.user).to eq(@user)
      expect(pb.project).to eq(@project)
      expect(pb.background).to eq(@public_bg)
    end

    it "allows a nil background" do
      pb = build(:persisted_background, user_id: @user.id, project_id: @project.id, background_id: nil)
      expect(pb).to be_valid
    end
  end

  context "presence validations" do
    it "requires a project_id when the user is present" do
      # user present avoids the nil-user crash in the read-access validator (see below).
      pb = build(:persisted_background, user_id: @user.id, project_id: nil)
      expect(pb).not_to be_valid
      expect(pb.errors[:project_id]).to be_present
    end

    # NOTE (reported to #294): the create-context read-access validator calls
    # Project.viewable(record.user) / Background.viewable(record.user) without
    # guarding against a nil user, so validating with a nil user raises
    # NoMethodError ("undefined method `admin?' for nil") instead of surfacing a
    # clean "user can't be blank" validation error. This pins the current behavior.
    it "raises on create validation when the user is nil (documents current fragility)" do
      pb = PersistedBackground.new(user_id: nil, project_id: @project.id)
      expect { pb.valid?(:create) }.to raise_error(NoMethodError, /admin\?/)
    end
  end

  context "uniqueness (on create)" do
    it "rejects a second persisted background for the same user+project" do
      create(:persisted_background, user_id: @user.id, project_id: @project.id, background_id: @public_bg.id)
      dup = build(:persisted_background, user_id: @user.id, project_id: @project.id, background_id: @public_bg.id)
      expect(dup).not_to be_valid
      expect(dup.errors[:base].join).to match(/already has a background persisted/)
    end
  end

  context "read-access validation (on create)" do
    it "rejects a background the user cannot view" do
      other_user = create(:user)
      other_project = create(:project, users: [other_user])
      other_s1 = create(:sample, project: other_project,
                                 pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED }])
      other_s2 = create(:sample, project: other_project,
                                 pipeline_runs_data: [{ finalized: 1, job_status: PipelineRun::STATUS_CHECKED }])
      private_bg = create(:background, user: other_user, name: "Private BG", public_access: 0, pipeline_run_ids: [
                            other_s1.first_pipeline_run.id,
                            other_s2.first_pipeline_run.id,
                          ])

      pb = build(:persisted_background, user_id: @user.id, project_id: @project.id, background_id: private_bg.id)
      expect(pb).not_to be_valid
      expect(pb.errors[:base].join).to match(/does not have read access to Background/)
    end

    it "rejects a project the user cannot view" do
      other_project = create(:project, users: [create(:user)])
      pb = build(:persisted_background, user_id: @user.id, project_id: other_project.id, background_id: @public_bg.id)
      expect(pb).not_to be_valid
      expect(pb.errors[:base].join).to match(/does not have read access to Project/)
    end
  end

  context "#viewable scope" do
    it "returns only records for the given user" do
      mine = create(:persisted_background, user_id: @user.id, project_id: @project.id, background_id: @public_bg.id)
      other_user = create(:user)
      other_project = create(:project, users: [other_user])
      other = create(:persisted_background, user_id: other_user.id, project_id: other_project.id, background_id: @public_bg.id)

      result = PersistedBackground.viewable(@user)
      expect(result).to include(mine)
      expect(result).not_to include(other)
    end
  end
end
