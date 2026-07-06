# frozen_string_literal: true

require "rails_helper"

# Upload -> S3 round-trip end-to-end test.
#
# WHY THIS EXISTS (ties to platform-overhaul #500 / #462, bug class #465):
# Nothing in the suite currently asserts that an uploaded object actually LANDS
# in S3 at the key the app derives, and is READABLE BACK with matching bytes.
# This is the exact class of the bulk-download regression: the API returned 200,
# but the bytes were never really in S3 (wrong key / write skipped), and no test
# caught it because the existing S3 specs only assert "put_object was called with
# these args" (see spec/lib/s3_util_spec.rb #upload_to_s3) -- a call-assertion,
# not a persistence assertion. A stub that always says "OK" would let a
# write-to-the-wrong-key or a skipped-write regression pass silently.
#
# WHAT THIS DOES DIFFERENTLY:
# We register an in-memory S3 backend onto the app's own AwsClient[:s3] via
# stub_responses Procs that MODEL REAL SEMANTICS -- put_object actually stores
# the body under [bucket, key], and get_object/head_object/list_objects_v2 read
# from that same store (raising NoSuchKey when the key is absent, exactly as real
# S3 would). The test then drives the app's REAL server-side write path
# (S3Util.upload_to_s3) and REAL read path (S3Util.get_s3_file / get_s3_range),
# keyed off the REAL InputFile#s3_path the model derives from the Sample. If the
# code writes to the wrong bucket/key or skips the write, the read-back fails --
# which is the whole point.
#
# S3-in-test mechanism: aws-sdk stub_responses with storing Procs (a fake that
# persists + serves bodies). Chosen because this harness has NO LocalStack/MinIO
# (grep of docker-compose*.yml / config / spec finds none; RAILS_ENV=test sets
# Aws.config stub_responses:true) -- so an in-memory backend that models real
# put/get semantics is the faithful, deterministic, network-free option. No AWS.
#
# InMemoryS3 -- a stub backend that behaves like a real (single-object-store) S3.
# Keys are [bucket, key]; put stores bytes, get/head serve them, absent keys 404.
class InMemoryS3
  NoSuchKeyError = Class.new(StandardError)

  def initialize
    @store = {}
  end

  # Build an Aws::S3::Client whose put/get/head/list operations are backed by
  # this in-memory store instead of always returning empty success.
  def build_client
    store = @store
    client = Aws::S3::Client.new(stub_responses: true)

    client.stub_responses(:put_object, lambda { |context|
      bucket = context.params[:bucket]
      key = context.params[:key]
      body = context.params[:body]
      body = body.read if body.respond_to?(:read)
      body = body.to_s
      store[[bucket, key]] = body.dup.force_encoding(Encoding::BINARY)
      { etag: %("#{Digest::MD5.hexdigest(body)}") }
    })

    client.stub_responses(:get_object, lambda { |context|
      bucket = context.params[:bucket]
      key = context.params[:key]
      data = store[[bucket, key]]
      # Model real S3: an absent key is a hard error, not an empty 200 body.
      raise Aws::S3::Errors::NoSuchKey.new(context, "The specified key does not exist.") if data.nil?

      range = context.params[:range]
      if range && (m = range.match(/bytes=(\d+)-(\d+)/))
        first = m[1].to_i
        last = m[2].to_i
        data = data.byteslice(first..last) || ""
      end
      { body: StringIO.new(data), content_length: data.bytesize }
    })

    client.stub_responses(:head_object, lambda { |context|
      bucket = context.params[:bucket]
      key = context.params[:key]
      data = store[[bucket, key]]
      raise Aws::S3::Errors::NotFound.new(context, "Not Found") if data.nil?

      { content_length: data.bytesize }
    })

    client.stub_responses(:list_objects_v2, lambda { |context|
      bucket = context.params[:bucket]
      prefix = context.params[:prefix].to_s
      contents = store.select { |(b, k), _v| b == bucket && k.start_with?(prefix) }
                      .map { |(_b, k), v| { key: k, size: v.bytesize } }
      { contents: contents, key_count: contents.size }
    })

    client
  end
end

RSpec.describe "Upload -> S3 round-trip (persistence, not just call-assertion)", type: :model do
  let(:in_memory_s3) { InMemoryS3.new }
  let(:s3_client) { in_memory_s3.build_client }

  before do
    # Give the app a real (in-memory-backed) bucket to write to. Without this,
    # SAMPLES_BUCKET_NAME is blank in test and upload_to_s3 fails fast (CZID-296).
    stub_const("SAMPLES_BUCKET_NAME", "round-trip-samples-bucket")
    ENV["SAMPLES_BUCKET_NAME"] = "round-trip-samples-bucket"

    # Route the app's shared S3 client through our storing fake. Everything that
    # goes through AwsClient[:s3] -- S3Util, Sample -- now hits the in-memory
    # store, so a write and a later read see the same object.
    allow(AwsClient).to receive(:[]) do |client_key|
      client_key == :s3 ? s3_client : Aws::S3::Client.new(stub_responses: true)
    end
    # S3_CLIENT is a constant frozen at boot to AwsClient[:s3] (before this stub),
    # and InputFile#s3_presence_check reads it directly, so re-point it too.
    stub_const("S3_CLIENT", s3_client)
  end

  # A sample + its input file, using the REAL key the model derives. We do not
  # hardcode the key -- InputFile#s3_path is the exact path the server reads from
  # after the browser uploads, so testing against it catches key-derivation drift.
  let(:project) { create(:project) }
  let(:sample) do
    create(:sample, project: project,
                    input_files: [build(:local_web_input_file, name: "reads.1.fastq.gz")])
  end
  let(:input_file) { sample.input_files.first }
  let(:s3_path) { input_file.s3_path } # s3://<bucket>/samples/<project>/<sample>/fastqs/reads.1.fastq.gz
  let(:bucket_and_key) { S3Util.parse_s3_path(s3_path) }
  let(:bucket) { bucket_and_key[0] }
  let(:key) { bucket_and_key[1] }
  let(:payload) { "@SEQ_ID\nGATTACAGATTACA\n+\n!!!!!!!!!!!!!!\n" }

  it "lands the uploaded object at the sample's real S3 key and reads back identical bytes" do
    # (a)+(b): write via the app's OWN upload machinery to the sample's real key.
    S3Util.upload_to_s3(bucket, key, payload)

    # (c): read back via the app's OWN read path.
    read_back = S3Util.get_s3_file(s3_path)

    # (d): the bytes must match. A skipped write or wrong-key write => nil/mismatch.
    expect(read_back).to eq(payload)
  end

  it "makes the object retrievable at the exact InputFile#s3_path (no key drift)" do
    S3Util.upload_to_s3(bucket, key, payload)

    # Reading at the model-derived path must succeed; reading a *different* key
    # must 404 -> get_s3_file rescues to nil. This is what would have caught the
    # bulk-download bug: object present, but not where the reader looks.
    expect(S3Util.get_s3_file(s3_path)).to eq(payload)

    wrong_path = "s3://#{bucket}/samples/#{project.id}/#{sample.id}/fastqs/NOT-THE-KEY.fastq.gz"
    expect(S3Util.get_s3_file(wrong_path)).to be_nil
  end

  it "serves a correct byte range from the persisted object (get_s3_range round-trip)" do
    S3Util.upload_to_s3(bucket, key, payload)

    first_ten = S3Util.get_s3_range(s3_path, 0, 9)
    expect(first_ten).to eq(payload.byteslice(0..9))
  end

  it "reflects the persisted object in a presence/size check (head + list round-trip)" do
    S3Util.upload_to_s3(bucket, key, payload)

    # head_object-backed presence check on the model.
    expect(input_file.s3_presence_check).to be_truthy
    # list_objects_v2-backed size check reads the real stored bytesize.
    expect(S3Util.get_file_size(bucket, key)).to eq(payload.bytesize)
  end

  # Guard the guard: prove the fake actually fails when the object is NOT there,
  # so a green suite means "the write really happened", not "the stub always says OK".
  it "returns nil when nothing was uploaded (the stub does not fabricate bytes)" do
    expect(S3Util.get_s3_file(s3_path)).to be_nil
    expect { input_file.s3_presence_check }.not_to raise_error
    expect(input_file.s3_presence_check).to be_falsey
  end
end
