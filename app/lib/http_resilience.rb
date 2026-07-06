# frozen_string_literal: true

require 'net/http'
require 'uri'

# HttpResilience wraps outbound calls to external SaaS (LocationIQ, Auth0, ...) in a
# lightweight in-process CIRCUIT BREAKER + bounded timeouts + retry-with-backoff.
#
# WHY: those calls used bare `Net::HTTP` with NO connect/read timeout and NO rescue.
# A single SaaS hang would tie up a Puma/worker thread indefinitely; a full outage
# would exhaust the pool and cascade into an app-wide stall. The circuit breaker
# fast-fails once a dependency is clearly down (open circuit) so the caller can
# degrade gracefully instead of every request paying the full timeout.
#
# This is a sibling to AegeaRetry (which guards `aegea` shell-outs to AWS): same
# house style — transient retries with exponential backoff + jitter, permanent
# failures surfaced immediately, everything greppable in the logs.
#
# Usage:
#   breaker = HttpResilience.breaker(:location_iq)
#   response = breaker.run { Net::HTTP.start(...) { |h| h.request(req) } }
#
#   # or fetch a body directly with timeouts baked in:
#   body = HttpResilience.breaker(:auth0_jwks).run do
#     HttpResilience.get(url, open_timeout: 3, read_timeout: 5)
#   end
#
# On an OPEN circuit, `run` raises HttpResilience::CircuitOpenError WITHOUT calling
# the block, so the caller can rescue it and return a cached/empty/degraded result.
module HttpResilience
  # Raised by CircuitBreaker#run when the circuit is open (dependency presumed down).
  class CircuitOpenError < StandardError; end

  # Default timeouts for the convenience HTTP helpers. Conservative but bounded so a
  # hung SaaS endpoint can never wedge a request thread.
  DEFAULT_OPEN_TIMEOUT = 3   # seconds to establish the TCP/TLS connection
  DEFAULT_READ_TIMEOUT = 8   # seconds to read the response

  # Circuit breaker defaults.
  DEFAULT_FAILURE_THRESHOLD = 5   # consecutive failures that trip the circuit open
  DEFAULT_RESET_TIMEOUT = 30      # seconds open before allowing a single trial (half-open)

  # A minimal, thread-safe consecutive-failure circuit breaker.
  #
  # States:
  #   :closed    — calls flow through; each failure increments the counter.
  #   :open       — calls fast-fail with CircuitOpenError until reset_timeout elapses.
  #   :half_open — one trial call is allowed; success closes the circuit, failure re-opens it.
  class CircuitBreaker
    attr_reader :name, :state

    def initialize(name, failure_threshold: DEFAULT_FAILURE_THRESHOLD,
                   reset_timeout: DEFAULT_RESET_TIMEOUT, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @name = name
      @failure_threshold = failure_threshold
      @reset_timeout = reset_timeout
      @clock = clock
      @mutex = Mutex.new
      @failure_count = 0
      @opened_at = nil
      @state = :closed
    end

    # Run the block through the breaker. Raises CircuitOpenError (without running the
    # block) when the circuit is open and the reset window has not yet elapsed.
    def run
      raise ArgumentError, 'block required' unless block_given?

      ensure_can_attempt!

      begin
        result = yield
        record_success
        result
      rescue StandardError => e
        record_failure
        raise e
      end
    end

    # True if the circuit is currently rejecting calls.
    def open?
      @mutex.synchronize { @state == :open && !reset_window_elapsed? }
    end

    private

    def ensure_can_attempt!
      @mutex.synchronize do
        case @state
        when :open
          if reset_window_elapsed?
            @state = :half_open
          else
            raise CircuitOpenError, "circuit '#{@name}' is open (last failure #{elapsed_since_open.round(1)}s ago)"
          end
        end
      end
    end

    def record_success
      @mutex.synchronize do
        @failure_count = 0
        @opened_at = nil
        @state = :closed
      end
    end

    def record_failure
      @mutex.synchronize do
        @failure_count += 1
        if @state == :half_open || @failure_count >= @failure_threshold
          @state = :open
          @opened_at = @clock.call
          log_open
        end
      end
    end

    def reset_window_elapsed?
      return true if @opened_at.nil?

      elapsed_since_open >= @reset_timeout
    end

    def elapsed_since_open
      return 0 if @opened_at.nil?

      @clock.call - @opened_at
    end

    def log_open
      msg = "[HttpResilience] circuit '#{@name}' OPEN after #{@failure_count} consecutive failures; " \
            "fast-failing for #{@reset_timeout}s"
      defined?(Rails) && Rails.logger ? Rails.logger.warn(msg) : warn(msg)
    end
  end

  module_function

  # Process-wide registry of breakers keyed by name, so all callers of the same
  # dependency share one circuit (a LocationIQ outage seen by one request opens it
  # for the rest). Thread-safe lazy init.
  def breaker(name, **opts)
    @registry_mutex ||= Mutex.new
    @registry ||= {}
    @registry_mutex.synchronize do
      @registry[name] ||= CircuitBreaker.new(name, **opts)
    end
  end

  # Test/reset hook — drop all registered breakers.
  def reset!
    @registry_mutex ||= Mutex.new
    @registry_mutex.synchronize { @registry = {} }
  end

  # Convenience GET with bounded timeouts + a small transient-retry loop. Returns the
  # response body String on success; raises on exhausted retries / permanent errors so
  # the surrounding breaker records the failure.
  #
  # Retries ONLY transient network/5xx conditions (timeouts, connection resets, 5xx).
  # A 4xx (bad request / not found) is returned to the caller as-is (no retry).
  def get(url, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
          max_attempts: 3, base_delay: 0.5, sleeper: nil)
    request(Net::HTTP::Get.new(URI(url)), URI(url),
            open_timeout: open_timeout, read_timeout: read_timeout,
            max_attempts: max_attempts, base_delay: base_delay, sleeper: sleeper)
  end

  # Perform an arbitrary Net::HTTP request object against `uri` with bounded timeouts
  # and transient retries. Returns the Net::HTTPResponse.
  def request(req, uri, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
              max_attempts: 3, base_delay: 0.5, sleeper: nil)
    sleeper ||= ->(s) { sleep(s) }
    uri = URI(uri) unless uri.is_a?(URI::Generic)
    attempt = 0

    begin
      attempt += 1
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      resp = http.start { |h| h.request(req) }

      # Retry only transient server-side 5xx; return everything else to the caller.
      raise TransientHttpError, "#{uri.host} -> #{resp.code}" if transient_status?(resp.code)

      resp
    rescue TransientHttpError, Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED,
           Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError,
           IOError => e
      if attempt >= max_attempts
        log_exhausted(uri, attempt, e)
        raise
      end
      delay = backoff_delay(attempt, base_delay)
      log_retry(uri, attempt, max_attempts, delay, e)
      sleeper.call(delay)
      retry
    end
  end

  # Internal sentinel so a retryable 5xx flows through the same rescue as network errors.
  class TransientHttpError < StandardError; end

  def transient_status?(code)
    %w[500 502 503 504].include?(code.to_s)
  end

  # Exponential backoff with +/-25% jitter, capped at 8s.
  def backoff_delay(attempt, base_delay, max_delay: 8.0, jitter: 0.25)
    raw = [base_delay * (2**(attempt - 1)), max_delay].min
    spread = raw * jitter
    rand([raw - spread, 0.0].max..(raw + spread))
  end

  def log_retry(uri, attempt, max_attempts, delay, err)
    msg = "[HttpResilience] transient GET #{uri.host} (attempt #{attempt}/#{max_attempts}); " \
          "retrying in #{delay.round(2)}s: #{err.class}: #{err.message}"
    defined?(Rails) && Rails.logger ? Rails.logger.warn(msg) : warn(msg)
  end

  def log_exhausted(uri, attempt, err)
    msg = "[HttpResilience] exhausted retries on #{uri.host} after #{attempt} attempts: " \
          "#{err.class}: #{err.message}"
    defined?(Rails) && Rails.logger ? Rails.logger.error(msg) : warn(msg)
  end
end
