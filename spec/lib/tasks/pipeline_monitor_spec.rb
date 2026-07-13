require "rails_helper"

# CheckPipelineRuns is defined in lib/tasks/pipeline_monitor.rake, which is loaded
# via Rails.application.load_tasks in rails_helper. These specs cover the defensive
# guards added for Forgejo #388 (the empty/blank JSON body was 532 Sentry events).
RSpec.describe CheckPipelineRuns do
  describe ".parse_json_or_nil" do
    it "returns nil for a blank body without raising" do
      expect(LogUtil).not_to receive(:log_error)
      expect(described_class.parse_json_or_nil("", "test")).to be_nil
      expect(described_class.parse_json_or_nil(nil, "test")).to be_nil
      expect(described_class.parse_json_or_nil("   ", "test")).to be_nil
    end

    it "returns nil and logs for an unparseable body instead of raising" do
      expect(LogUtil).to receive(:log_error).with(/Failed to parse JSON/, hash_including(:exception))
      expect(described_class.parse_json_or_nil("{not json", "test")).to be_nil
    end

    it "parses valid JSON" do
      expect(described_class.parse_json_or_nil('{"a":1}', "test")).to eq("a" => 1)
    end
  end

  describe ".benchmark_update" do
    it "no-ops on an empty benchmark config body instead of raising JSON::ParserError" do
      # Simulate `aws s3 cp ... -` returning an empty body (missing object / creds hiccup).
      allow(described_class).to receive(:`).and_return("")
      expect { described_class.benchmark_update(Time.now.to_f) }.not_to raise_error
    end

    it "no-ops when the config is present but has no active_benchmarks" do
      allow(described_class).to receive(:`).and_return('{"defaults":{}}')
      expect { described_class.benchmark_update(Time.now.to_f) }.not_to raise_error
    end
  end
end
