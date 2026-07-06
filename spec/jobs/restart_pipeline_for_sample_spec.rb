require "rails_helper"

RSpec.describe RestartPipelineForSample, type: :job do
  create_users

  let(:project) { create(:project, users: [@joe]) }
  let(:sample) { create(:sample, project: project, user: @joe) }

  describe "#perform" do
    it "kicks off the pipeline for the identified sample" do
      allow(Sample).to receive(:find).with(sample.id).and_return(sample)
      expect(sample).to receive(:kickoff_pipeline).and_return(true)
      RestartPipelineForSample.perform(sample.id)
    end

    context "when kickoff_pipeline returns falsey" do
      before do
        allow(Sample).to receive(:find).with(sample.id).and_return(sample)
        allow(sample).to receive(:kickoff_pipeline).and_return(false)
      end

      it "logs the error and re-raises a 'not restarted' error" do
        expect(LogUtil).to receive(:log_error).with(
          a_string_matching(/RestartPipelineForSample #{sample.id} failed to run/),
          exception: an_instance_of(RuntimeError),
          sample_id: sample.id
        )
        expect do
          RestartPipelineForSample.perform(sample.id)
        end.to raise_error("not restarted")
      end
    end

    it "logs and raises RecordNotFound when the sample does not exist" do
      expect(LogUtil).to receive(:log_error).with(
        a_string_matching(/RestartPipelineForSample -1 failed to run/),
        exception: an_instance_of(ActiveRecord::RecordNotFound),
        sample_id: -1
      )
      expect do
        RestartPipelineForSample.perform(-1)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
