require 'rails_helper'

RSpec.describe AmrGeneLevelDownloadsService, type: :service do
  let(:index_id) { "gene-123" }

  let(:workflow_run) { instance_double(AmrWorkflowRun) }
  let(:fake_s3_client) { double("s3_client") }

  let(:s3_bam_path) { "s3://fake-bucket/path/output.bam" }
  let(:s3_bai_path) { "s3://fake-bucket/path/output.bam.bai" }
  let(:presigned_url) { "https://fake-bucket.s3.amazonaws.com/path/output.bam?signed=true" }

  before do
    allow(AwsClient).to receive(:[]).with(:s3).and_return(fake_s3_client)
    allow(fake_s3_client).to receive(:get_object).and_return(true)
    allow_any_instance_of(AmrGeneLevelDownloadsService).to receive(:get_presigned_s3_url).and_return(presigned_url)
    allow(Syscall).to receive(:pipe_with_output).and_return("")
  end

  describe "#call" do
    context "for a contigs download" do
      before do
        allow(workflow_run).to receive(:output_path)
          .with(AmrWorkflowRun::OUTPUT_CONTIGS_BAM).and_return(s3_bam_path)
        allow(workflow_run).to receive(:output_path)
          .with(AmrWorkflowRun::OUTPUT_CONTIGS_BAI).and_return(s3_bai_path)
      end

      subject do
        AmrGeneLevelDownloadsService.call(
          workflow_run,
          AmrGeneLevelDownloadsService::DOWNLOAD_TYPE_CONTIGS,
          index_id
        )
      end

      it "resolves the contigs BAM/BAI output paths" do
        subject
        expect(workflow_run).to have_received(:output_path).with(AmrWorkflowRun::OUTPUT_CONTIGS_BAM)
        expect(workflow_run).to have_received(:output_path).with(AmrWorkflowRun::OUTPUT_CONTIGS_BAI)
      end

      it "downloads the .bai index from S3" do
        subject
        expect(fake_s3_client).to have_received(:get_object).with(
          hash_including(bucket: "fake-bucket", key: "path/output.bam.bai")
        )
      end

      it "pipes samtools with the presigned url and index id, returning the output path" do
        result = subject
        expect(Syscall).to have_received(:pipe_with_output).with(
          array_including("samtools", "view", "-h", "-X", presigned_url, index_id),
          a_string_matching(/samtools fasta/)
        )
        expect(result).to be_a(String)
      end
    end

    context "for a reads download" do
      before do
        allow(workflow_run).to receive(:output_path)
          .with(AmrWorkflowRun::OUTPUT_READS_BAM).and_return(s3_bam_path)
        allow(workflow_run).to receive(:output_path)
          .with(AmrWorkflowRun::OUTPUT_READS_BAI).and_return(s3_bai_path)
      end

      subject do
        AmrGeneLevelDownloadsService.call(
          workflow_run,
          AmrGeneLevelDownloadsService::DOWNLOAD_TYPE_READS,
          index_id
        )
      end

      it "resolves the reads BAM/BAI output paths" do
        subject
        expect(workflow_run).to have_received(:output_path).with(AmrWorkflowRun::OUTPUT_READS_BAM)
        expect(workflow_run).to have_received(:output_path).with(AmrWorkflowRun::OUTPUT_READS_BAI)
      end

      it "returns a path from the samtools pipeline" do
        expect(subject).to be_a(String)
      end
    end
  end
end
