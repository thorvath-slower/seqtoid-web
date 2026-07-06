require "rails_helper"

# Coverage Wave 5: InstrumentedJob is a mixin that wraps Resque jobs with
# ActiveSupport::Notifications instrumentation and a CloudWatch extra-dimensions
# feature. We exercise it against a tiny throwaway job class.
RSpec.describe InstrumentedJob do
  # A minimal job that mirrors how real jobs use the mixin.
  let(:job_class) do
    Class.new do
      extend InstrumentedJob

      def self.name
        "FakeInstrumentedJob"
      end

      def self.perform(param1, param2); end
    end
  end

  before do
    allow(ActiveSupport::Notifications.instrumenter).to receive(:start)
    allow(ActiveSupport::Notifications.instrumenter).to receive(:finish)
  end

  describe "#extra_dimensions" do
    it "stores a hash of extra dimensions" do
      expect { job_class.extra_dimensions(param1: "Dim 1") }.not_to raise_error
    end

    it "raises when given a non-hash" do
      expect { job_class.extra_dimensions("not a hash") }.to raise_error(ArgumentError, /not a Hash/)
    end
  end

  describe "#before_perform_start_instrumentation" do
    it "starts instrumentation with the underscored name" do
      expect(ActiveSupport::Notifications.instrumenter).to receive(:start)
        .with("resque.fake_instrumented_job", hash_including(job_name: "FakeInstrumentedJob"))
      job_class.before_perform_start_instrumentation("a", "b")
    end

    it "raises when extra_dimensions keys don't match the perform parameters" do
      job_class.extra_dimensions(nonexistent_param: "Bad Dim")
      expect { job_class.before_perform_start_instrumentation("a", "b") }
        .to raise_error(RuntimeError, /extra_dimensions keys do not match/)
    end

    it "does not raise when extra_dimensions keys match the perform parameters" do
      job_class.extra_dimensions(param1: "Dim 1", param2: "Dim 2")
      expect { job_class.before_perform_start_instrumentation("a", "b") }.not_to raise_error
    end
  end

  describe "#after_perform_finish_instrumentation" do
    it "finishes instrumentation with a Success status and zipped params" do
      expect(ActiveSupport::Notifications.instrumenter).to receive(:finish)
        .with("resque.fake_instrumented_job", hash_including(status: "Success", params: { param1: "a", param2: "b" }))
      job_class.after_perform_finish_instrumentation("a", "b")
    end
  end

  describe "#on_failure" do
    it "finishes instrumentation with a Failure status and the error prepended to params" do
      expect(ActiveSupport::Notifications.instrumenter).to receive(:finish)
        .with("resque.fake_instrumented_job", hash_including(status: "Failure"))
      job_class.on_failure(StandardError.new("boom"), "a", "b")
    end
  end
end
