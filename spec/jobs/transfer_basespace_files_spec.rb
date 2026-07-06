require "rails_helper"

# Coverage Wave 5: TransferBasespaceFiles orchestrates the basespace -> S3 file
# transfer and the shared access-token revocation. We stub the sample transfer
# and BasespaceHelper so no real HTTP/S3 happens, and drive each branch of the
# "last sample done -> revoke token" logic including the tolerated 401.
RSpec.describe TransferBasespaceFiles, type: :job do
  create_users

  let(:project) { create(:project, users: [@joe]) }
  let(:access_token) { "fake-access-token" }
  let(:dataset_id) { "dataset-123" }
  let(:sample) do
    create(:sample, project: project, user: @joe, basespace_access_token: access_token, status: Sample::STATUS_CREATED)
  end

  before do
    allow_any_instance_of(Sample).to receive(:transfer_basespace_fastq_files).and_return(true)
    allow(BasespaceHelper).to receive(:revoke_access_token)
    allow(BasespaceHelper).to receive(:verify_access_token_revoked)
  end

  describe ".perform" do
    it "transfers files for the sample" do
      expect_any_instance_of(Sample).to receive(:transfer_basespace_fastq_files).with(dataset_id, access_token)
      TransferBasespaceFiles.perform(sample.id, dataset_id, access_token)
    end

    context "when no samples remain on the token" do
      before do
        # After transfer, mark the sample as no longer STATUS_CREATED so the "remaining" query is empty.
        allow_any_instance_of(Sample).to receive(:transfer_basespace_fastq_files) do
          sample.update!(status: Sample::STATUS_CHECKED)
        end
      end

      it "revokes and verifies the access token" do
        expect(BasespaceHelper).to receive(:revoke_access_token).with(access_token)
        expect(BasespaceHelper).to receive(:verify_access_token_revoked).with(access_token, sample.id)
        TransferBasespaceFiles.perform(sample.id, dataset_id, access_token)
      end

      it "tolerates a 401 from revoke_access_token (already revoked)" do
        allow(BasespaceHelper).to receive(:revoke_access_token)
          .and_raise(HttpHelper::HttpError.new("unauthorized", 401))
        expect(BasespaceHelper).to receive(:verify_access_token_revoked)
        expect { TransferBasespaceFiles.perform(sample.id, dataset_id, access_token) }.not_to raise_error
      end

      it "re-raises non-401 http errors from revoke_access_token" do
        allow(BasespaceHelper).to receive(:revoke_access_token)
          .and_raise(HttpHelper::HttpError.new("server error", 500))
        allow(LogUtil).to receive(:log_error)
        expect { TransferBasespaceFiles.perform(sample.id, dataset_id, access_token) }
          .to raise_error(HttpHelper::HttpError)
      end
    end

    context "when other samples still remain on the token" do
      let!(:other_sample) do
        create(:sample, project: project, user: @joe, basespace_access_token: access_token, status: Sample::STATUS_CREATED)
      end

      it "does not revoke the token" do
        expect(BasespaceHelper).not_to receive(:revoke_access_token)
        TransferBasespaceFiles.perform(sample.id, dataset_id, access_token)
      end
    end

    context "when the sample transfer raises" do
      before do
        allow_any_instance_of(Sample).to receive(:transfer_basespace_fastq_files).and_raise(StandardError, "boom")
        allow(LogUtil).to receive(:log_error)
      end

      it "logs the error and re-raises" do
        expect(LogUtil).to receive(:log_error).with(/Error transferring basespace files/, hash_including(sample_id: sample.id))
        expect { TransferBasespaceFiles.perform(sample.id, dataset_id, access_token) }.to raise_error(StandardError, "boom")
      end
    end
  end
end
