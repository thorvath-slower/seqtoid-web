# frozen_string_literal: true

require "rails_helper"

RSpec.describe CloudWatchUtil do
  describe ".create_metric_datum" do
    it "builds a metric datum hash with the expected shape and defaults" do
      frozen = Time.utc(2026, 1, 1, 12, 0, 0)
      allow(Time).to receive(:current).and_return(frozen)

      datum = CloudWatchUtil.create_metric_datum("uploads", 5.0, "Count")

      expect(datum).to eq(
        metric_name: "uploads",
        dimensions: [],
        timestamp: frozen,
        value: 5.0,
        unit: "Count",
        storage_resolution: 60
      )
    end

    it "passes through provided dimensions" do
      dimensions = [{ name: "env", value: "test" }]
      datum = CloudWatchUtil.create_metric_datum("m", 1.0, "None", dimensions)
      expect(datum[:dimensions]).to eq(dimensions)
    end

    it "uses a 60-second (1-minute) storage resolution" do
      datum = CloudWatchUtil.create_metric_datum("m", 1.0, "None")
      expect(datum[:storage_resolution]).to eq(60)
    end
  end

  describe ".put_metric_data" do
    # In the test environment the method is a deliberate no-op (guards against
    # emitting real CloudWatch metrics from CI). We assert that contract.
    it "is a no-op in the test environment and does not touch the AWS client" do
      # Guard: the method early-returns when RAILS_ENV == 'test' so CI never emits
      # real CloudWatch metrics. If AwsClient were called, this expectation trips.
      expect(AwsClient).not_to receive(:[]) if defined?(AwsClient)
      expect(ENV["RAILS_ENV"]).to eq("test")
      expect(CloudWatchUtil.put_metric_data("Namespace", [])).to be_nil
    end
  end
end
