require 'rails_helper'

# Supplementary coverage for BulkDownload (Coverage Wave 4b).
#
# CHARACTERIZATION: pins the CURRENT behavior of the #kickoff_ecs_task failure
# branch, which surfaced in live Sentry (ucsf-rm, dev) as a RuntimeError whose
# message embeds a Python "Traceback ..." string carried straight through from
# the shelled-out aegea/s3_tar_writer stderr. This is a characterization spec of
# existing behavior, NOT a fix -- when the underlying bug (raising the raw
# Python traceback string as a RuntimeError instead of a structured error) is
# addressed, this expectation is expected to change. Tracked as a Forgejo bug.
RSpec.describe BulkDownload, type: :model do
  create_users

  let(:python_traceback_stderr) do
    <<~STDERR
      Traceback (most recent call last):
        File "s3_tar_writer.py", line 42, in <module>
          main()
        File "s3_tar_writer.py", line 30, in main
          raise ValueError("boom")
      ValueError: boom
    STDERR
  end

  describe "#kickoff_ecs_task (failure branch)" do
    let(:bulk_download) { create(:bulk_download, user: @joe, download_type: "sample_overview", status: BulkDownload::STATUS_WAITING) }
    let(:failed_status) { instance_double(Process::Status, exitstatus: 1) }

    before do
      # Avoid touching the real filesystem/tempfiles + aegea command construction.
      allow(bulk_download).to receive(:aegea_ecs_submit_command).and_return(["aegea", "ecs", "run"])
      allow(AegeaRetry).to receive(:capture3).and_return(["", python_traceback_stderr, failed_status])
    end

    it "raises the raw stderr (carrying the Python traceback) verbatim" do
      expect { bulk_download.kickoff_ecs_task(["echo", "hi"]) }
        .to raise_error(RuntimeError, /Traceback \(most recent call last\)/)
    end

    it "marks the download errored with the kickoff-failure message before raising" do
      expect { bulk_download.kickoff_ecs_task(["echo", "hi"]) }.to raise_error(RuntimeError)
      bulk_download.reload
      expect(bulk_download.status).to eq(BulkDownload::STATUS_ERROR)
      expect(bulk_download.error_message).to eq(BulkDownloadsHelper::KICKOFF_FAILURE)
    end
  end

  describe "#kickoff_ecs_task (success branch)" do
    let(:bulk_download) { create(:bulk_download, user: @joe, download_type: "sample_overview", status: BulkDownload::STATUS_WAITING) }
    let(:ok_status) { instance_double(Process::Status, exitstatus: 0) }

    before do
      allow(bulk_download).to receive(:aegea_ecs_submit_command).and_return(["aegea", "ecs", "run"])
      allow(AegeaRetry).to receive(:capture3).and_return([{ "taskArn" => "arn:aws:ecs:task/abc" }.to_json, "", ok_status])
    end

    it "records the task arn and marks the download running" do
      bulk_download.kickoff_ecs_task(["echo", "hi"])
      bulk_download.reload
      expect(bulk_download.ecs_task_arn).to eq("arn:aws:ecs:task/abc")
      expect(bulk_download.status).to eq(BulkDownload::STATUS_RUNNING)
    end
  end
end
