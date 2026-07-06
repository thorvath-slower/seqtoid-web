# frozen_string_literal: true

require "rails_helper"
require "stringio"

# S3TarWriter streams a gzipped tar to `aws s3 cp - <dest>` via Open3.popen2.
# We replace the popen2 stdin with an in-memory StringIO (and stub the wait thread)
# so we exercise the real TarWriter/GzipWriter framing + byte accounting WITHOUT
# shelling out to the aws CLI. We then read the captured bytes back to prove the
# archive is a valid gzip'd tar containing the written files.
RSpec.describe S3TarWriter do
  let(:dest) { "s3://fake-bucket/downloads/out.tar.gz" }

  # A StringIO that tolerates #binmode (Open3's real stdin supports it).
  let(:captured_stdin) do
    io = StringIO.new(+"".b)
    def io.binmode
      set_encoding(Encoding::BINARY)
      self
    end
    io
  end

  let(:fake_status) { instance_double(Process::Status, success?: true) }
  let(:fake_wait_thr) { double("wait_thr", value: fake_status) }

  before do
    allow(Open3).to receive(:popen2)
      .with("aws", "s3", "cp", "-", dest)
      .and_return([captured_stdin, StringIO.new, fake_wait_thr])
  end

  def read_archive(bytes)
    gz = Zlib::GzipReader.new(StringIO.new(bytes))
    tar = Gem::Package::TarReader.new(gz)
    entries = {}
    tar.each { |e| entries[e.full_name] = e.read }
    entries
  ensure
    tar&.close
  end

  it "invokes aws s3 cp streaming to the destination on start_streaming" do
    writer = described_class.new(dest)
    writer.start_streaming
    expect(Open3).to have_received(:popen2).with("aws", "s3", "cp", "-", dest)
  end

  it "writes files into a valid gzipped tar and accounts total bytes" do
    writer = described_class.new(dest)
    writer.start_streaming
    writer.add_file_with_data("a.txt", "hello")
    writer.add_file_with_data("b.txt", "world!!")
    writer.close

    expect(writer.total_size_processed).to eq("hello".bytesize + "world!!".bytesize)

    entries = read_archive(captured_stdin.string)
    expect(entries).to eq("a.txt" => "hello", "b.txt" => "world!!")
  end

  it "counts bytes correctly for multibyte (UTF-8) content" do
    writer = described_class.new(dest)
    writer.start_streaming
    data = "héllo" # 'é' is 2 bytes in UTF-8
    writer.add_file_with_data("u.txt", data)
    writer.close

    expect(writer.total_size_processed).to eq(data.bytesize)
    expect(writer.total_size_processed).to be > data.length
  end

  it "starts with zero bytes processed" do
    expect(described_class.new(dest).total_size_processed).to eq(0)
  end

  it "exposes the aws process exit status via process_status" do
    writer = described_class.new(dest)
    writer.start_streaming
    expect(writer.process_status.success?).to be(true)
  end
end
