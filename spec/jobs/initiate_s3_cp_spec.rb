require "rails_helper"

RSpec.describe InitiateS3Cp, type: :job do
  create_users

  describe "#perform" do
    let(:project) { create(:project, users: [@joe]) }
    let(:sample) { create(:sample, project: project, user: @joe) }

    it "copies the sample's fastq files and restarts a failed upload workflow run" do
      allow(Sample).to receive(:find).with(sample.id).and_return(sample)
      expect(sample).to receive(:initiate_fastq_files_s3_cp).with(false).and_return("copied")
      expect(WorkflowRun).to receive(:handle_sample_upload_restart).with(sample)
      InitiateS3Cp.perform(sample.id)
    end

    it "forwards the unlimited_size flag to the sample copy" do
      allow(Sample).to receive(:find).with(sample.id).and_return(sample)
      expect(sample).to receive(:initiate_fastq_files_s3_cp).with(true).and_return("copied")
      allow(WorkflowRun).to receive(:handle_sample_upload_restart)
      InitiateS3Cp.perform(sample.id, true)
    end

    it "resets the latest failed workflow run to created (real handle_sample_upload_restart effect)" do
      allow(Sample).to receive(:find).with(sample.id).and_return(sample)
      allow(sample).to receive(:initiate_fastq_files_s3_cp).and_return("copied")
      failed_run = create(:workflow_run, sample: sample, status: WorkflowRun::STATUS[:failed])

      InitiateS3Cp.perform(sample.id)

      expect(failed_run.reload.status).to eq(WorkflowRun::STATUS[:created])
    end

    it "raises RecordNotFound when the sample does not exist" do
      expect do
        InitiateS3Cp.perform(-1)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
