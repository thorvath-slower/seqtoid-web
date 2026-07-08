# frozen_string_literal: true

require "rails_helper"

# Specs for the #496 OpenSearch circuit-breaker wrapper. The wrapper delegates to
# the wrapped client while a shared HttpResilience breaker is closed, records
# failures, and fast-fails with CircuitOpenError once the threshold is crossed.
RSpec.describe OpensearchCircuit do
  # A tiny fake ES client. `search` returns a canned value or raises depending on
  # how the spec sets it up; `indices` returns a namespaced proxy so we can assert
  # passthrough of the return value.
  let(:fake_client) do
    Class.new do
      attr_accessor :fail_times, :calls

      def initialize
        @fail_times = 0
        @calls = 0
      end

      def search(*_args, **_kwargs)
        @calls += 1
        if @calls <= @fail_times
          raise StandardError, "boom #{@calls}"
        end

        { "hits" => { "total" => 1 } }
      end

      def count(*_args)
        42
      end
    end.new
  end

  after { HttpResilience.reset! }

  around do |example|
    original = ENV.to_hash
    example.run
  ensure
    ENV.replace(original)
  end

  describe ".wrap" do
    it "returns the raw client untouched when the breaker is disabled" do
      ENV["OPENSEARCH_BREAKER_ENABLED"] = "0"
      expect(described_class.wrap(fake_client)).to equal(fake_client)
    end

    it "returns nil untouched (test env builds no client)" do
      expect(described_class.wrap(nil)).to be_nil
    end

    it "wraps the client when enabled" do
      ENV["OPENSEARCH_BREAKER_ENABLED"] = "1"
      expect(described_class.wrap(fake_client)).to be_a(described_class)
    end
  end

  describe "delegation (healthy path)" do
    subject(:wrapped) { described_class.wrap(fake_client, name: :test_os) }

    it "forwards calls and returns the client's value verbatim" do
      expect(wrapped.search(index: "x")).to eq("hits" => { "total" => 1 })
      expect(wrapped.count).to eq(42)
    end

    it "reports respond_to? for delegated methods" do
      expect(wrapped).to respond_to(:search)
      expect(wrapped).not_to respond_to(:definitely_not_a_method)
    end

    it "raises NoMethodError for methods the client does not have" do
      expect { wrapped.definitely_not_a_method }.to raise_error(NoMethodError)
    end
  end

  describe "circuit breaker behavior" do
    before do
      ENV["OPENSEARCH_BREAKER_FAILURE_THRESHOLD"] = "3"
      ENV["OPENSEARCH_BREAKER_RESET_TIMEOUT"] = "30"
    end

    subject(:wrapped) { described_class.wrap(fake_client, name: :test_os_breaker) }

    it "re-raises the underlying error while the circuit is closed" do
      fake_client.fail_times = 2
      2.times { expect { wrapped.search }.to raise_error(StandardError, /boom/) }
      # third call succeeds now that failures are exhausted
      expect(wrapped.search).to eq("hits" => { "total" => 1 })
    end

    it "opens the circuit after the failure threshold and fast-fails without calling the client" do
      fake_client.fail_times = 99
      3.times { expect { wrapped.search }.to raise_error(StandardError, /boom/) }
      calls_before = fake_client.calls
      expect { wrapped.search }.to raise_error(HttpResilience::CircuitOpenError)
      # the client was NOT invoked on the open-circuit call
      expect(fake_client.calls).to eq(calls_before)
    end
  end

  describe "ENV knobs" do
    it "reads threshold and reset timeout from ENV with safe defaults" do
      ENV.delete("OPENSEARCH_BREAKER_FAILURE_THRESHOLD")
      ENV.delete("OPENSEARCH_BREAKER_RESET_TIMEOUT")
      expect(described_class.failure_threshold).to eq(HttpResilience::DEFAULT_FAILURE_THRESHOLD)
      expect(described_class.reset_timeout).to eq(HttpResilience::DEFAULT_RESET_TIMEOUT)

      ENV["OPENSEARCH_BREAKER_FAILURE_THRESHOLD"] = "7"
      ENV["OPENSEARCH_BREAKER_RESET_TIMEOUT"] = "12"
      expect(described_class.failure_threshold).to eq(7)
      expect(described_class.reset_timeout).to eq(12)
    end
  end
end
