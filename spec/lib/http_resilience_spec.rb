# frozen_string_literal: true

require "rails_helper"

# Specs for the #467 resilience helper that guards outbound SaaS calls (Auth0,
# LocationIQ). These were deferred when the helper shipped; this closes that gap.
#
# The circuit-breaker state machine is exercised deterministically: we inject a
# controllable clock (a lambda over a mutable `now`) so the reset window advances
# by assignment, never by real sleep -> fast + non-flaky (#516). Transient-retry
# tests inject a no-op sleeper and stub Net::HTTP so no real network is touched.
RSpec.describe HttpResilience do
  # A hand-cranked monotonic clock. `now` is advanced explicitly in the specs.
  let(:fake_now) { { t: 1000.0 } }
  let(:clock) { -> { fake_now[:t] } }

  def advance(seconds)
    fake_now[:t] += seconds
  end

  after { described_class.reset! }

  describe HttpResilience::CircuitBreaker do
    subject(:breaker) do
      described_class.new(:dep, failure_threshold: 3, reset_timeout: 30, clock: clock)
    end

    it "starts closed and runs the block, returning its value" do
      expect(breaker.state).to eq(:closed)
      expect(breaker.run { 42 }).to eq(42)
      expect(breaker.state).to eq(:closed)
    end

    it "raises ArgumentError when no block is given" do
      expect { breaker.run }.to raise_error(ArgumentError, /block required/)
    end

    it "propagates the block's exception while closed and counts it" do
      expect { breaker.run { raise "boom" } }.to raise_error(RuntimeError, "boom")
      expect(breaker.state).to eq(:closed)
    end

    it "opens only after the failure threshold of consecutive failures" do
      # 2 failures (< threshold of 3): still closed.
      2.times do
        expect { breaker.run { raise "boom" } }.to raise_error("boom")
      end
      expect(breaker.state).to eq(:closed)

      # 3rd consecutive failure trips it open.
      expect { breaker.run { raise "boom" } }.to raise_error("boom")
      expect(breaker.state).to eq(:open)
    end

    it "resets the failure counter on an intervening success (failures must be consecutive)" do
      2.times { expect { breaker.run { raise "boom" } }.to raise_error("boom") }
      breaker.run { :ok } # success resets the counter
      expect(breaker.state).to eq(:closed)

      # Two more failures again do NOT trip it (counter was reset to 0).
      2.times { expect { breaker.run { raise "boom" } }.to raise_error("boom") }
      expect(breaker.state).to eq(:closed)
    end

    context "when open" do
      before do
        3.times { expect { breaker.run { raise "boom" } }.to raise_error("boom") }
        expect(breaker.state).to eq(:open)
      end

      it "fast-fails with CircuitOpenError WITHOUT running the block" do
        ran = false
        expect { breaker.run { ran = true } }.to raise_error(HttpResilience::CircuitOpenError)
        expect(ran).to be(false)
      end

      it "reports open? true before the reset window elapses" do
        advance(29) # still < reset_timeout of 30
        expect(breaker.open?).to be(true)
      end

      it "reports open? false once the reset window has elapsed" do
        advance(30)
        expect(breaker.open?).to be(false)
      end

      it "allows one half-open trial after the reset window and CLOSES on success" do
        advance(31)
        ran = false
        result = breaker.run do
          ran = true
          :recovered
        end
        expect(ran).to be(true)
        expect(result).to eq(:recovered)
        expect(breaker.state).to eq(:closed)
      end

      it "re-opens immediately on a failed half-open trial (single failure, not threshold)" do
        advance(31)
        expect { breaker.run { raise "still down" } }.to raise_error("still down")
        expect(breaker.state).to eq(:open)

        # And it fast-fails again right after re-opening.
        expect { breaker.run { :never } }.to raise_error(HttpResilience::CircuitOpenError)
      end

      it "keeps fast-failing while still inside the reset window" do
        advance(10)
        expect { breaker.run { :never } }.to raise_error(HttpResilience::CircuitOpenError)
        expect(breaker.state).to eq(:open)
      end
    end
  end

  describe ".breaker registry" do
    it "returns the same breaker instance for the same name (shared circuit)" do
      a = described_class.breaker(:shared)
      b = described_class.breaker(:shared)
      expect(a).to be(b)
    end

    it "returns distinct breakers for different names" do
      expect(described_class.breaker(:one)).not_to be(described_class.breaker(:two))
    end

    it "reset! drops registered breakers so a fresh instance is created" do
      first = described_class.breaker(:dropme)
      described_class.reset!
      expect(described_class.breaker(:dropme)).not_to be(first)
    end
  end

  describe ".transient_status?" do
    it "treats 5xx server errors as transient" do
      %w[500 502 503 504].each do |code|
        expect(described_class.transient_status?(code)).to be(true)
      end
    end

    it "does not treat 2xx/4xx as transient" do
      %w[200 301 400 404 429].each do |code|
        expect(described_class.transient_status?(code)).to be(false)
      end
    end

    it "accepts integer codes as well as strings" do
      expect(described_class.transient_status?(503)).to be(true)
      expect(described_class.transient_status?(404)).to be(false)
    end
  end

  describe ".backoff_delay" do
    it "grows exponentially in expectation and stays within the +/-25% jitter band" do
      base = 0.5
      # attempt 1 -> raw 0.5, attempt 2 -> 1.0, attempt 3 -> 2.0
      { 1 => 0.5, 2 => 1.0, 3 => 2.0 }.each do |attempt, raw|
        100.times do
          d = described_class.backoff_delay(attempt, base)
          expect(d).to be >= (raw * 0.75).round(6) - 1e-9
          expect(d).to be <= (raw * 1.25) + 1e-9
        end
      end
    end

    it "caps the raw delay at max_delay before jitter" do
      # attempt 10 would be 0.5 * 2^9 = 256s raw; capped to 8s, then +/-25%.
      100.times do
        d = described_class.backoff_delay(10, 0.5)
        expect(d).to be <= 8.0 * 1.25 + 1e-9
        expect(d).to be >= 8.0 * 0.75 - 1e-9
      end
    end
  end

  describe ".request (transient retry loop)" do
    let(:uri) { "https://example.test/path" }
    let(:req) { Net::HTTP::Get.new(URI(uri)) }
    let(:no_sleep) { ->(_s) { nil } }

    # Build a fake Net::HTTP whose #start yields a fake response with the given code.
    def stub_http_returning(*codes)
      responses = codes.map do |code|
        instance_double(Net::HTTPResponse, code: code.to_s, body: "body-#{code}")
      end
      call = 0
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:start) do |&_blk|
        resp = responses[call] || responses.last
        call += 1
        resp
      end
      http
    end

    it "returns the response immediately on a 2xx (no retry)" do
      http = stub_http_returning(200)
      resp = described_class.request(req, uri, sleeper: no_sleep)
      expect(resp.code).to eq("200")
      expect(http).to have_received(:start).once
    end

    it "returns a 4xx to the caller as-is without retrying" do
      http = stub_http_returning(404)
      resp = described_class.request(req, uri, sleeper: no_sleep)
      expect(resp.code).to eq("404")
      expect(http).to have_received(:start).once
    end

    it "retries a transient 5xx and succeeds when a later attempt is healthy" do
      http = stub_http_returning(503, 502, 200)
      resp = described_class.request(req, uri, max_attempts: 3, sleeper: no_sleep)
      expect(resp.code).to eq("200")
      expect(http).to have_received(:start).exactly(3).times
    end

    it "raises after exhausting retries on persistent 5xx" do
      http = stub_http_returning(500)
      expect do
        described_class.request(req, uri, max_attempts: 3, sleeper: no_sleep)
      end.to raise_error(HttpResilience::TransientHttpError)
      expect(http).to have_received(:start).exactly(3).times
    end

    it "retries transient network errors (e.g. ECONNRESET) then re-raises when exhausted" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:start).and_raise(Errno::ECONNRESET)

      expect do
        described_class.request(req, uri, max_attempts: 2, sleeper: no_sleep)
      end.to raise_error(Errno::ECONNRESET)
      expect(http).to have_received(:start).exactly(2).times
    end

    it "honours max_attempts (a single attempt does not retry)" do
      http = stub_http_returning(503)
      expect do
        described_class.request(req, uri, max_attempts: 1, sleeper: no_sleep)
      end.to raise_error(HttpResilience::TransientHttpError)
      expect(http).to have_received(:start).once
    end

    it "sleeps between attempts using the injected sleeper (bounded backoff)" do
      stub_http_returning(503, 200)
      slept = []
      described_class.request(req, uri, max_attempts: 3, base_delay: 0.5,
                                        sleeper: ->(s) { slept << s })
      expect(slept.size).to eq(1)
      expect(slept.first).to be > 0
    end
  end

  describe ".get" do
    it "issues a GET and returns the response body on success" do
      body = '{"ok":true}'
      http = instance_double(Net::HTTP)
      resp = instance_double(Net::HTTPResponse, code: "200", body: body)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:start).and_return(resp)

      out = described_class.get("https://example.test/x", sleeper: ->(_s) { nil })
      expect(out.body).to eq(body)
    end
  end

  describe "integration: breaker wrapping a flapping dependency" do
    it "opens after repeated real failures then fast-fails the wrapped block" do
      breaker = described_class.new(:integration, failure_threshold: 2,
                                                  reset_timeout: 5, clock: clock)
      attempts = 0
      failing = lambda do
        attempts += 1
        raise IOError, "dep down"
      end

      2.times { expect { breaker.run(&failing) }.to raise_error(IOError) }
      expect(breaker.state).to eq(:open)
      expect(attempts).to eq(2)

      # Now the block must NOT run.
      expect { breaker.run(&failing) }.to raise_error(HttpResilience::CircuitOpenError)
      expect(attempts).to eq(2)
    end
  end
end
