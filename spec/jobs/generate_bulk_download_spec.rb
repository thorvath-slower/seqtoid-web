require "rails_helper"

RSpec.describe GenerateBulkDownload, type: :job do
  create_users

  describe "#perform" do
    let(:bulk_download) { create(:bulk_download, user: @joe) }

    it "invokes generate_download_file on the identified BulkDownload" do
      expect(BulkDownload).to receive(:find).with(bulk_download.id).and_return(bulk_download)
      expect(bulk_download).to receive(:generate_download_file)
      GenerateBulkDownload.perform(bulk_download.id)
    end

    context "when generation fails" do
      before do
        allow(BulkDownload).to receive(:find).with(bulk_download.id).and_return(bulk_download)
        allow(bulk_download).to receive(:generate_download_file).and_raise(StandardError.new("boom"))
      end

      it "logs the error and re-raises so the on_failure hook fires" do
        expect(LogUtil).to receive(:log_error).with(
          "Bulk download generation failed for id #{bulk_download.id}: boom",
          exception: an_instance_of(StandardError),
          bulk_download_id: bulk_download.id
        )
        expect do
          GenerateBulkDownload.perform(bulk_download.id)
        end.to raise_error(StandardError, "boom")
      end
    end

    it "logs and raises RecordNotFound when the bulk download does not exist" do
      allow(LogUtil).to receive(:log_error)
      expect do
        GenerateBulkDownload.perform(-1)
      end.to raise_error(ActiveRecord::RecordNotFound)
      expect(LogUtil).to have_received(:log_error).with(
        a_string_matching(/Bulk download generation failed for id -1/),
        exception: an_instance_of(ActiveRecord::RecordNotFound),
        bulk_download_id: -1
      )
    end
  end
end
