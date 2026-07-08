# frozen_string_literal: true

require "rails_helper"

# Specs for the #496 retry+DLQ mixin. We assert the mixin wires up resque-retry's
# ExponentialBackoff with sane defaults and registers a give-up callback that
# dead-letters the job. The retry state-machine itself is resque-retry's (already
# tested upstream); here we verify our configuration + dead-letter routing.
RSpec.describe ResqueRetryWithDeadLetter do
  let(:job_class) do
    Class.new do
      extend ResqueRetryWithDeadLetter
      @queue = :test_retry_dlq
      def self.name
        "TestRetryDlqJob"
      end

      def self.perform(*_args)
      end
    end
  end

  describe "wiring" do
    it "extends the job with resque-retry ExponentialBackoff" do
      expect(job_class.singleton_class.included_modules).to include(Resque::Plugins::ExponentialBackoff)
    end

    it "retries on StandardError by default" do
      expect(job_class.instance_variable_get(:@retry_exceptions)).to eq([StandardError])
    end

    it "uses the default backoff schedule (4 attempts)" do
      expect(job_class.instance_variable_get(:@backoff_strategy)).to eq(ResqueRetryWithDeadLetter::DEFAULT_BACKOFF)
      expect(job_class.retry_limit).to eq(ResqueRetryWithDeadLetter::DEFAULT_BACKOFF.length)
    end
  end

  describe "give-up dead-letters the job" do
    it "records the job to the DeadLetterQueue when retries are exhausted" do
      exception = StandardError.new("permanent-ish")
      expect(DeadLetterQueue).to receive(:record).with("TestRetryDlqJob", [1, "a"], exception)
      # Drive resque-retry's give-up callback path directly.
      job_class.run_give_up_callbacks(exception, 1, "a")
    end
  end

  describe ".default_backoff" do
    around do |example|
      original = ENV["WORKER_RETRY_BACKOFF"]
      example.run
    ensure
      ENV["WORKER_RETRY_BACKOFF"] = original
    end

    it "parses a comma-separated ENV override" do
      ENV["WORKER_RETRY_BACKOFF"] = "0, 10, 60"
      expect(described_class.default_backoff).to eq([0, 10, 60])
    end

    it "falls back to the default on a malformed override" do
      ENV["WORKER_RETRY_BACKOFF"] = "not,a,number"
      expect(described_class.default_backoff).to eq(described_class::DEFAULT_BACKOFF)
    end

    it "falls back to the default when unset" do
      ENV.delete("WORKER_RETRY_BACKOFF")
      expect(described_class.default_backoff).to eq(described_class::DEFAULT_BACKOFF)
    end
  end

  describe "configure_retry_with_dead_letter override" do
    it "allows per-job backoff and exception overrides" do
      job_class.configure_retry_with_dead_letter(backoff: [0, 5], retry_exceptions: [ArgumentError])
      expect(job_class.instance_variable_get(:@backoff_strategy)).to eq([0, 5])
      expect(job_class.instance_variable_get(:@retry_exceptions)).to eq([ArgumentError])
    end
  end
end
