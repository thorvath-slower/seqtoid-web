require "rails_helper"

RSpec.describe S3Util do
  let(:fake_database_bucket) { "fake-database-bucket" }
  let(:ontology_file_key) { "amr/ontology/2020-01-01/aro.json" }
  let(:test_expression) { "SELECT * FROM S3Object[*].NorA LIMIT 1" }
  let(:sample_gene_response) { "{\"label\":\"norA\",\"accession\":\"3000391\",\"description\":\"NorA is an AMR gene.\",\"synonyms\":[],\"publications\":[\"Publication 1. (PMID 31415926)\",\"Publication 2. (PMID 12345678)\",\"Publication 3. (PMID 98765432)\"],\"geneFamily\":[{\"label\":\"gene family label\",\"description\":\"gene family description.\"}],\"drugClass\":{\"label\":\"Drug class\",\"description\":\"Drug class description.\"},\"genbankAccession\":\"HE123456\"}," }
  let(:successful_stream_response) do
    [
      {
        message_type: 'event',
        event_type: 'records',
        payload: StringIO.new(sample_gene_response),
      },
    ].each
  end
  before do
    @mock_aws_clients = {
      s3: Aws::S3::Client.new(stub_responses: true),
    }
    allow(AwsClient).to receive(:[]) { |client|
      @mock_aws_clients[client]
    }
  end

  describe "#s3_select_json" do
    # this test uses the example of getting information on a single gene
    # from a JSON file with information about many genes
    it "should return a single string on success" do
      @mock_aws_clients[:s3].stub_responses(:select_object_content, { payload: successful_stream_response })
      entry = S3Util.s3_select_json(fake_database_bucket, ontology_file_key, test_expression)
      expect(entry).to be_instance_of(String)
      expect(entry).to eq(sample_gene_response)
    end

    # On error (like a gene name not found in the json file), return a blank string.
    it "handles errors from S3" do
      # S3 Select surfaces a server-side failure as an Aws::S3::Errors::ServiceError,
      # which s3_select_json rescues and turns into "". (CZID-119: the old in-stream
      # error-event stub format is no longer valid under aws-sdk-core 3.248.)
      @mock_aws_clients[:s3].stub_responses(:select_object_content, 'InternalError')
      expect { S3Util.s3_select_json(fake_database_bucket, ontology_file_key, test_expression) }.not_to raise_error
      entry = S3Util.s3_select_json(fake_database_bucket, ontology_file_key, test_expression)
      expect(entry).to be_instance_of(String)
      expect(entry.blank?).to be_truthy
    end
  end

  describe "#abort_multipart_uploads" do
    let(:bucket) { "fake-samples-bucket" }
    let(:prefix) { "samples/1/2/" }

    it "aborts every incomplete multipart upload under the prefix" do
      @mock_aws_clients[:s3].stub_responses(
        :list_multipart_uploads,
        {
          uploads: [
            { key: "samples/1/2/fastqs/file.1.fastq.gz", upload_id: "upload-a" },
            { key: "samples/1/2/fastqs/file.2.fastq.gz", upload_id: "upload-b" },
          ],
        }
      )

      aborted_args = []
      allow(@mock_aws_clients[:s3]).to receive(:abort_multipart_upload) do |args|
        aborted_args << args
      end

      count = S3Util.abort_multipart_uploads(bucket, prefix)

      expect(count).to eq(2)
      expect(aborted_args).to contain_exactly(
        { bucket: bucket, key: "samples/1/2/fastqs/file.1.fastq.gz", upload_id: "upload-a" },
        { bucket: bucket, key: "samples/1/2/fastqs/file.2.fastq.gz", upload_id: "upload-b" }
      )
    end

    it "does nothing when there are no incomplete multipart uploads" do
      @mock_aws_clients[:s3].stub_responses(:list_multipart_uploads, { uploads: [] })
      expect(@mock_aws_clients[:s3]).not_to receive(:abort_multipart_upload)
      expect(S3Util.abort_multipart_uploads(bucket, prefix)).to eq(0)
    end
  end
end
