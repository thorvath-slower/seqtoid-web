require "rails_helper"

describe InputFile, type: :model do
  let(:user) { create(:user) }
  let(:project) { create(:project, users: [user]) }
  let(:sample) { create(:sample, project: project) }

  context "#s3_presence_check" do
    it "returns true if head_object on the file succeeds" do
      expect(sample.input_files[0].s3_presence_check).to be true
      expect(sample.input_files[1].s3_presence_check).to be true
    end

    it "returns false if head_object on the file fails" do
      expect(S3_CLIENT).to receive(:head_object).exactly(2).times.and_raise(Aws::S3::Errors::NotFound.new(nil, nil))

      expect(sample.input_files[0].s3_presence_check).to be false
      expect(sample.input_files[1].s3_presence_check).to be false
    end
  end

  context ".split_name" do
    it "splits a paired bulk fastq into prefix + suffix" do
      expect(InputFile.split_name("sample_R1_001.fastq.gz")).to eq(["sample", "_R1_001.fastq.gz"])
    end

    it "splits a single bulk fasta" do
      expect(InputFile.split_name("sample.fasta")).to eq(["sample", ".fasta"])
    end

    # CZID-118: reference/primer files (e.g. .bed) are valid (FILE_REGEX) but not
    # bulk fastq/fasta, so they hit the fallback branch — which used to reference
    # the instance method #file_extension from this class method and raise NameError.
    it "splits a non-bulk file (primer .bed) without raising" do
      expect(InputFile.split_name("primer.bed")).to eq(["primer", ".bed"])
      expect(InputFile.split_name("ref.bed.gz")).to eq(["ref", ".bed.gz"])
    end

    it "falls back to File.extname for an unrecognized format" do
      expect(InputFile.split_name("weird.txt")).to eq(["weird", ".txt"])
    end
  end
end
