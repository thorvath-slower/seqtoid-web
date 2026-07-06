require 'rails_helper'

# Coverage Wave 2 (branch): input_file_spec.rb covers split_name + s3_presence_check;
# this fills the s3_source_check validation branches and the file_extension /
# hash_name conditionals.
describe InputFile, type: :model do
  let(:user) { create(:user) }
  let(:project) { create(:project, users: [user]) }
  let(:sample) { create(:sample, project: project) }

  describe "#file_extension" do
    it "returns the extension for a well-formed name" do
      f = build(:local_web_input_file, name: "reads.fastq.gz")
      expect(f.file_extension).to eq("fastq.gz")
    end

    it "returns nil when the name doesn't match the file regex" do
      f = InputFile.new(name: "not a valid name!!")
      expect(f.file_extension).to be_nil
    end
  end

  describe ".hash_name" do
    it "preserves the suffix after hashing the prefix" do
      hashed = InputFile.hash_name("sample_R1_001.fastq.gz", "somesalt")
      expect(hashed).to end_with("_R1_001.fastq.gz")
    end
  end

  describe "#s3_source_check (on create)" do
    def build_s3_input(source:, bulk_mode: false)
      s = create(:sample, project: project, bulk_mode: bulk_mode)
      InputFile.new(
        sample: s,
        name: "reads.fastq.gz",
        source: source,
        source_type: InputFile::SOURCE_TYPE_S3,
        upload_client: InputFile::UPLOAD_CLIENT_WEB,
        file_type: InputFile::FILE_TYPE_FASTQ
      )
    end

    it "is skipped entirely for non-s3 source types" do
      f = InputFile.new(
        sample: sample, name: "reads.fastq.gz", source: "reads.fastq.gz",
        source_type: InputFile::SOURCE_TYPE_LOCAL,
        upload_client: InputFile::UPLOAD_CLIENT_WEB, file_type: InputFile::FILE_TYPE_FASTQ
      )
      expect(f).to be_valid
    end

    it "rejects an s3 source that doesn't start with s3://" do
      f = build_s3_input(source: "http://not-s3/x")
      expect(f).not_to be_valid
      expect(f.errors[:input_files].join).to match(/doesn't start with s3/)
    end

    it "rejects an s3 source the user is not allowed to upload from" do
      f = build_s3_input(source: "s3://idseq-secret/x")
      allow_any_instance_of(User).to receive(:can_upload).and_return(false)
      expect(f).not_to be_valid
      expect(f.errors[:input_files].join).to match(/forbidden s3 bucket/)
    end

    it "skips the object head check in bulk mode (elsif !bulk_mode false branch)" do
      f = build_s3_input(source: "s3://ok-bucket/x", bulk_mode: true)
      allow_any_instance_of(User).to receive(:can_upload).and_return(true)
      expect(Syscall).not_to receive(:pipe_with_output)
      expect(f).to be_valid
    end

    it "rejects an empty s3 object in non-bulk mode" do
      f = build_s3_input(source: "s3://ok-bucket/x", bulk_mode: false)
      allow_any_instance_of(User).to receive(:can_upload).and_return(true)
      allow(Syscall).to receive(:pipe_with_output).and_return("")
      expect(f).not_to be_valid
      expect(f.errors[:input_files].join).to match(/forbidden file object/)
    end

    it "accepts a non-empty s3 object in non-bulk mode" do
      f = build_s3_input(source: "s3://ok-bucket/x", bulk_mode: false)
      allow_any_instance_of(User).to receive(:can_upload).and_return(true)
      allow(Syscall).to receive(:pipe_with_output).and_return("some-header-bytes")
      expect(f).to be_valid
    end
  end
end
