require 'rails_helper'

RSpec.describe DeletionLog, type: :model do
  let(:user) { create(:user) }

  def build_log(**attrs)
    DeletionLog.new({ object_id: 1, user_id: user.id, object_type: Sample.name }.merge(attrs))
  end

  context "associations" do
    it "belongs to a user" do
      log = build_log
      expect(log.user).to eq(user)
    end

    it "is invalid without a user" do
      log = build_log(user_id: nil)
      log.user = nil
      expect(log).not_to be_valid
      expect(log.errors[:user]).to be_present
    end
  end

  context "object_type inclusion" do
    it "accepts Sample" do
      expect(build_log(object_type: Sample.name)).to be_valid
    end

    it "accepts PipelineRun" do
      expect(build_log(object_type: PipelineRun.name)).to be_valid
    end

    it "accepts WorkflowRun" do
      expect(build_log(object_type: WorkflowRun.name)).to be_valid
    end

    it "rejects an unknown object_type" do
      log = build_log(object_type: "Project")
      expect(log).not_to be_valid
      expect(log.errors[:object_type]).to be_present
    end

    it "rejects a nil object_type" do
      log = build_log(object_type: nil)
      expect(log).not_to be_valid
      expect(log.errors[:object_type]).to be_present
    end
  end
end
