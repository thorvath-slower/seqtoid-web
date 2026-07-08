# frozen_string_literal: true

require "rails_helper"

# Specs for the #496 dead-letter queue: exhausted Resque jobs are recorded durably
# (capped Redis list) and surfaced via LogUtil so they are visible, not lost.
RSpec.describe DeadLetterQueue do
  before { described_class.clear }
  after { described_class.clear }

  describe ".record" do
    it "persists an entry and fires a LogUtil error" do
      expect(LogUtil).to receive(:log_error).with(
        /exhausted retries and was dead-lettered/,
        hash_including(:exception, :dead_letter)
      )

      entry = described_class.record("IndexTaxons", [1, 2], StandardError.new("boom"))

      expect(entry["job"]).to eq("IndexTaxons")
      expect(entry["args"]).to eq([1, 2])
      expect(entry["error_class"]).to eq("StandardError")
      expect(entry["error"]).to eq("boom")
      expect(entry["failed_at"]).to be_present

      expect(described_class.count).to eq(1)
      expect(described_class.entries.first["job"]).to eq("IndexTaxons")
    end

    it "never raises even if persistence fails" do
      allow(described_class).to receive(:persist).and_raise("redis down")
      allow(LogUtil).to receive(:log_error)
      expect { described_class.record("X", [], StandardError.new("e")) }.not_to raise_error
    end

    it "keeps newest entries first" do
      allow(LogUtil).to receive(:log_error)
      described_class.record("First", [], StandardError.new("1"))
      described_class.record("Second", [], StandardError.new("2"))
      expect(described_class.entries.map { |e| e["job"] }).to eq(%w[Second First])
    end
  end

  describe ".entries limit" do
    it "honors the requested limit" do
      allow(LogUtil).to receive(:log_error)
      5.times { |i| described_class.record("J#{i}", [], StandardError.new("e")) }
      expect(described_class.entries(2).size).to eq(2)
    end
  end
end
