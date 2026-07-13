require "rails_helper"

RSpec.describe AegeaRetry do
  let(:cmd) { ["aegea", "ecs", "run", "--cluster", "test"] }
  let(:ok_status) { instance_double(Process::Status, exitstatus: 0, success?: true) }
  let(:fail_status) { instance_double(Process::Status, exitstatus: 1, success?: false) }

  # No-op sleeper so tests never actually block on backoff.
  let(:no_sleep) { ->(_seconds) {} }

  describe ".capture3" do
    it "returns immediately on first-try success (behaves like Open3.capture3)" do
      expect(Open3).to receive(:capture3).exactly(1).times.with(*cmd).and_return(
        ["OK", "", ok_status]
      )

      stdout, stderr, status = described_class.capture3(*cmd, sleeper: no_sleep)

      expect(stdout).to eq("OK")
      expect(stderr).to eq("")
      expect(status).to eq(ok_status)
    end

    it "retries a transient failure and then succeeds" do
      expect(Open3).to receive(:capture3).exactly(2).times.and_return(
        ["", "An error occurred (ThrottlingException): Rate exceeded", fail_status],
        ["OK", "", ok_status]
      )

      stdout, _stderr, status = described_class.capture3(*cmd, sleeper: no_sleep)

      expect(stdout).to eq("OK")
      expect(status).to eq(ok_status)
    end

    it "does NOT retry a permanent failure and returns the failing tuple" do
      expect(Open3).to receive(:capture3).exactly(1).times.and_return(
        ["", "An error occurred (AccessDenied): not authorized", fail_status]
      )

      stdout, stderr, status = described_class.capture3(*cmd, sleeper: no_sleep)

      expect(stdout).to eq("")
      expect(stderr).to include("AccessDenied")
      expect(status).to eq(fail_status)
    end

    it "exhausts retries on persistent transient failures and returns the last tuple" do
      expect(Open3).to receive(:capture3).exactly(4).times.and_return(
        ["", "Rate exceeded (ThrottlingException)", fail_status]
      )

      stdout, stderr, status = described_class.capture3(*cmd, sleeper: no_sleep)

      expect(stdout).to eq("")
      expect(stderr).to include("Rate exceeded")
      expect(status).to eq(fail_status)
    end

    it "honors a custom max_attempts" do
      expect(Open3).to receive(:capture3).exactly(2).times.and_return(
        ["", "connection reset by peer", fail_status]
      )

      described_class.capture3(*cmd, max_attempts: 2, sleeper: no_sleep)
    end

    it "sleeps between retries using the injected sleeper" do
      slept = []
      sleeper = ->(seconds) { slept << seconds }

      allow(Open3).to receive(:capture3).and_return(
        ["", "timed out", fail_status],
        ["OK", "", ok_status]
      )

      described_class.capture3(*cmd, sleeper: sleeper)

      expect(slept.length).to eq(1)
      expect(slept.first).to be > 0
    end

    it "also inspects stdout for transient signals (not just stderr)" do
      expect(Open3).to receive(:capture3).exactly(2).times.and_return(
        ["Service Unavailable", "", fail_status],
        ["OK", "", ok_status]
      )

      stdout, = described_class.capture3(*cmd, sleeper: no_sleep)
      expect(stdout).to eq("OK")
    end
  end

  describe ".retryable?" do
    transient = [
      "An error occurred (ThrottlingException) when calling RunTask",
      "Rate exceeded",
      "TooManyRequestsException",
      "RequestLimitExceeded",
      "insufficient capacity to satisfy the request",
      "InsufficientInstanceCapacity",
      "ServiceUnavailable: Service Unavailable",
      "An internal server error occurred",
      "InternalFailure",
      "connection reset by peer",
      "Connection refused",
      "Read timeout on endpoint URL",
      "Connect timeout on endpoint URL",
      "connection aborted",
      "Broken pipe",
      "timed out",
      "temporarily unavailable",
      "Name or service not known",
      "502 Bad Gateway",
      "503 Service Unavailable",
      "504 Gateway Time-out",
      "EndpointConnectionError: Could not connect to the endpoint URL",
      "SlowDown: Please reduce your request rate",
    ]

    permanent = [
      "An error occurred (AccessDenied) when calling RunTask",
      "UnauthorizedOperation",
      "ClusterNotFoundException: Cluster not found",
      "An error occurred (ValidationException)",
      "InvalidParameterException: cluster name is invalid",
      "NoSuchBucket: The specified bucket does not exist",
      "ExpiredToken: The security token included in the request is expired",
      "usage: aegea ecs run [-h] ...",  # bad args
      "An error occurred",              # generic, unclassified -> not retried
    ]

    transient.each do |msg|
      it "classifies as retryable: #{msg}" do
        expect(described_class.retryable?(msg)).to be(true)
      end
    end

    permanent.each do |msg|
      it "classifies as permanent: #{msg}" do
        expect(described_class.retryable?(msg)).to be(false)
      end
    end

    it "treats nil as not retryable" do
      expect(described_class.retryable?(nil)).to be(false)
    end
  end

  describe ".backoff_delay" do
    it "grows exponentially with attempt number" do
      # jitter=0 for determinism
      d1 = described_class.backoff_delay(1, 2.0, 30.0, 0)
      d2 = described_class.backoff_delay(2, 2.0, 30.0, 0)
      d3 = described_class.backoff_delay(3, 2.0, 30.0, 0)

      expect(d1).to eq(2.0)
      expect(d2).to eq(4.0)
      expect(d3).to eq(8.0)
    end

    it "caps at max_delay" do
      d = described_class.backoff_delay(10, 2.0, 30.0, 0)
      expect(d).to eq(30.0)
    end

    it "applies jitter within the expected band" do
      100.times do
        d = described_class.backoff_delay(2, 2.0, 30.0, 0.5)
        # base = 4.0, jitter 0.5 -> [2.0, 6.0]
        expect(d).to be_between(2.0, 6.0)
      end
    end
  end
end
