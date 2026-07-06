require "rails_helper"

RSpec.describe DeleteOldBulkDownloads, type: :job do
  create_users

  let(:old_age) { (BulkDownload::AUTO_DELETE_AFTER_NUM_DAYS + 1).days.ago }
  let(:recent_age) { (BulkDownload::AUTO_DELETE_AFTER_NUM_DAYS - 1).days.ago }

  before do
    # after_destroy :cleanup_s3 hits S3 — stub it so deletion stays offline.
    allow(S3Util).to receive(:delete_s3_prefix)
    # The job sleeps between batches (and on retry backoff); skip the waits.
    allow(DeleteOldBulkDownloads).to receive(:sleep)
  end

  describe "#perform" do
    context "when auto-deletion appconfig is disabled" do
      before do
        AppConfigHelper.set_app_config(AppConfig::AUTO_DELETE_OLD_BULK_DOWNLOADS, "0")
      end

      it "does not delete any bulk downloads, even old ones" do
        old_bd = create(:bulk_download, user: @joe, created_at: old_age)
        expect { DeleteOldBulkDownloads.perform }.not_to change(BulkDownload, :count)
        expect { old_bd.reload }.not_to raise_error
      end
    end

    context "when auto-deletion appconfig is enabled" do
      before do
        AppConfigHelper.set_app_config(AppConfig::AUTO_DELETE_OLD_BULK_DOWNLOADS, "1")
      end

      it "deletes bulk downloads older than the retention window" do
        old_bd = create(:bulk_download, user: @joe, created_at: old_age)
        expect { DeleteOldBulkDownloads.perform }.to change(BulkDownload, :count).by(-1)
        expect { old_bd.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "keeps bulk downloads within the retention window" do
        recent_bd = create(:bulk_download, user: @joe, created_at: recent_age)
        expect { DeleteOldBulkDownloads.perform }.not_to change(BulkDownload, :count)
        expect { recent_bd.reload }.not_to raise_error
      end

      it "deletes only the old records when both old and recent exist" do
        old_bd = create(:bulk_download, user: @joe, created_at: old_age)
        recent_bd = create(:bulk_download, user: @joe, created_at: recent_age)
        DeleteOldBulkDownloads.perform
        expect { old_bd.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect { recent_bd.reload }.not_to raise_error
      end

      it "triggers S3 cleanup for each deleted record" do
        create(:bulk_download, user: @joe, created_at: old_age)
        expect(S3Util).to receive(:delete_s3_prefix).once
        DeleteOldBulkDownloads.perform
      end
    end

    context "when an unexpected error occurs" do
      before do
        AppConfigHelper.set_app_config(AppConfig::AUTO_DELETE_OLD_BULK_DOWNLOADS, "1")
        allow(BulkDownload).to receive(:count).and_raise(StandardError.new("db down"))
      end

      it "logs the error and re-raises" do
        expect(LogUtil).to receive(:log_error).with(
          "Unexpected error encountered during DeleteOldBulkDownloads job.",
          exception: an_instance_of(StandardError)
        )
        expect { DeleteOldBulkDownloads.perform }.to raise_error(StandardError, "db down")
      end
    end
  end

  describe ".destory_bulk_download_with_retries" do
    before do
      AppConfigHelper.set_app_config(AppConfig::AUTO_DELETE_OLD_BULK_DOWNLOADS, "1")
    end

    it "retries and logs an error after exhausting attempts when destroy keeps failing" do
      old_bd = create(:bulk_download, user: @joe, created_at: old_age)
      allow_any_instance_of(BulkDownload).to receive(:destroy!).and_raise(StandardError.new("nope"))

      expect(LogUtil).to receive(:log_error).with(
        a_string_matching(/BulkDownload auto-deletion error while destroying id=#{old_bd.id}/),
        exception: an_instance_of(StandardError),
        bulk_download_id: old_bd.id
      )

      DeleteOldBulkDownloads.perform
      expect { old_bd.reload }.not_to raise_error
    end
  end
end
