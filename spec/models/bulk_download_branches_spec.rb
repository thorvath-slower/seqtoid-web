# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for BulkDownload. Targets the pure-ish command /
# key builders whose conditional arms the existing coverage spec (kickoff only)
# leaves untaken: download_output_key's three format arms, s3_tar_writer_command's
# url-present/absent branches (including the mandatory success_url raise), and
# aegea_ecs_submit_command's executable-path and configured-image branches.
RSpec.describe BulkDownload, type: :model do
  create_users

  describe "#download_output_key" do
    # Build (not create) to avoid params_checks; download_output_key is a pure
    # key builder that only reads download_type + the download_format param.
    it "appends .fa for a concatenated consensus_genome download (the CG single-file arm)" do
      bd = build(:bulk_download, user: @joe,
                                 download_type: BulkDownloadTypesHelper::CONSENSUS_GENOME_DOWNLOAD_TYPE)
      allow(bd).to receive(:id).and_return(1)
      allow(bd).to receive(:get_param_value).with("download_format")
                                            .and_return(BulkDownloadTypesHelper::SINGLE_FILE_CONCATENATED_DOWNLOAD)

      expect(bd.download_output_key).to end_with(".fa")
    end

    it "appends .biom for a biom_format download (the biom elsif arm)" do
      bd = build(:bulk_download, user: @joe,
                                 download_type: BulkDownloadTypesHelper::BIOM_FORMAT_DOWNLOAD_TYPE)
      allow(bd).to receive(:id).and_return(1)
      allow(bd).to receive(:get_param_value).and_return(nil)
      expect(bd.download_output_key).to end_with(".biom")
    end

    it "appends .tar.gz for any other download type (the else arm)" do
      bd = create(:bulk_download, user: @joe, download_type: "sample_overview")
      expect(bd.download_output_key).to end_with(".tar.gz")
    end
  end

  describe "#s3_tar_writer_command" do
    let(:bd) { create(:bulk_download, user: @joe, download_type: "sample_overview") }

    it "includes success/error/progress url flags when all are present (the truthy arms)" do
      command = bd.s3_tar_writer_command(
        ["s3://src"], ["name"], "s3://dest",
        success_url: "http://ok", error_url: "http://err", progress_url: "http://prog"
      )
      expect(command).to include("--success-url", "http://ok")
      expect(command).to include("--error-url", "http://err")
      expect(command).to include("--progress-url", "http://prog")
    end

    it "omits the optional error/progress flags when they are nil (the else arms)" do
      command = bd.s3_tar_writer_command(
        ["s3://src"], ["name"], "s3://dest",
        success_url: "http://ok", error_url: nil, progress_url: nil
      )
      expect(command).not_to include("--error-url")
      expect(command).not_to include("--progress-url")
    end

    it "raises when the mandatory success_url is missing (the success_url else)" do
      expect do
        bd.s3_tar_writer_command(["s3://src"], ["name"], "s3://dest", success_url: nil)
      end.to raise_error(BulkDownloadsHelper::SUCCESS_URL_REQUIRED)
    end

    it "strips leading dashes from tar names so they aren't parsed as flags" do
      command = bd.s3_tar_writer_command(
        ["s3://src"], ["--evil-name"], "s3://dest", success_url: "http://ok"
      )
      expect(command).to include("evil-name")
      expect(command).not_to include("--evil-name")
    end
  end

  describe "#aegea_ecs_submit_command" do
    let(:bd) { create(:bulk_download, user: @joe, download_type: "sample_overview") }

    it "adds the staging bucket flag when an executable path is present (the present? branch)" do
      allow(bd).to receive(:get_app_config).and_return(nil)
      command = bd.send(:aegea_ecs_submit_command, executable_file_path: "/tmp/exec.sh")
      expect(command).to include("--staging-s3-bucket")
      expect(command.join(" ")).to include("--execute=/tmp/exec.sh")
    end

    it "omits the staging bucket flag when no executable path is given (the absent branch)" do
      allow(bd).to receive(:get_app_config).and_return(nil)
      command = bd.send(:aegea_ecs_submit_command, executable_file_path: nil)
      expect(command).not_to include("--staging-s3-bucket")
    end

    it "uses the configured ECR image when app config provides one (the config non-nil branch)" do
      allow(bd).to receive(:get_app_config).and_return("custom-image:sha")
      command = bd.send(:aegea_ecs_submit_command, executable_file_path: "/tmp/exec.sh")
      expect(command).to include("custom-image:sha")
    end
  end
end
