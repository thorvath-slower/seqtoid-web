require 'open3'

# AegeaRetry wraps `aegea` shell-outs (which call AWS: ECS/Batch/ECR/S3) in a
# retry-with-exponential-backoff-and-jitter loop.
#
# aegea fails intermittently on transient AWS conditions (API throttling, ECS/Batch
# capacity, transient network / connection resets, 5xx responses, timeouts). Without
# a retry a single transient blip kills a whole bulk-download / job submit. This
# helper retries ONLY on those transient signals and surfaces permanent failures
# (bad args, unknown cluster, AccessDenied, etc.) immediately with the real stderr.
#
# Usage:
#   stdout, stderr, status = AegeaRetry.capture3(*aegea_command)
#
# On the happy path (first-try success) this behaves exactly like Open3.capture3.
# On exhausted retries it returns the last (stdout, stderr, status) tuple so the
# caller's existing error handling still sees the real stderr.
module AegeaRetry
  # Retry policy.
  DEFAULT_MAX_ATTEMPTS = 4        # total attempts (1 initial + 3 retries)
  DEFAULT_BASE_DELAY = 2.0        # seconds; first backoff ~2s
  DEFAULT_MAX_DELAY = 30.0        # seconds; cap so we don't sleep unboundedly
  DEFAULT_JITTER = 0.5 # +/- fraction of the computed delay

  # Transient failures worth retrying. Matched case-insensitively against the
  # combined stdout+stderr of a failed (non-zero exit) invocation. Each entry is
  # a documented AWS / network transient signal:
  RETRYABLE_PATTERNS = [
    # --- API throttling / rate limiting (retry after backoff) ---
    /throttl/i,                       # ThrottlingException / Throttling
    /rate exceeded/i,                 # generic AWS "Rate exceeded"
    /toomanyrequests/i,               # TooManyRequestsException (ECS/Batch)
    /requestlimitexceeded/i,          # RequestLimitExceeded
    /slow ?down/i,                    # S3 SlowDown
    /provisionedthroughputexceeded/i, # DynamoDB-backed throttle
    # --- ECS / Batch / capacity (transient placement / scale-up) ---
    /capacity/i,                      # "insufficient capacity", capacity provider
    /insufficientinstancecapacity/i,  # EC2/Fargate scale-up race
    /resource.*not.*available/i,      # transient resource unavailability
    /service.*unavailable/i,          # ServiceUnavailable
    # --- Transient server-side (5xx) ---
    /serviceunavailable/i,
    /internal ?server ?error/i, # 500 InternalServerError / InternalError
    /internalerror/i,
    /internalfailure/i,
    /\b50[0234]\b/,                    # bare 500/502/503/504 status codes
    /bad ?gateway/i,                   # 502
    /gateway ?time-?out/i,             # 504
    # --- Transient network / connection ---
    /connection reset/i,              # ECONNRESET
    /connection refused/i,            # ECONNREFUSED (transient endpoint blip)
    /connection aborted/i,
    /broken pipe/i,                   # EPIPE
    /reset by peer/i,
    /timed out/i,                     # socket / read timeout
    /timeout/i,                       # ReadTimeoutError / connect timeout
    /temporarily unavailable/i,       # EAGAIN / transient DNS
    /name or service not known/i,     # transient DNS resolution failure
    /could not connect/i,
    /econnreset|etimedout|econnrefused|enetunreach|ehostunreach/i,
    /endpointconnectionerror/i,       # botocore transient endpoint error
    /read timeout on endpoint/i,      # botocore ReadTimeoutError
    /connect timeout on endpoint/i,   # botocore ConnectTimeoutError
  ].freeze

  # NOTE ON DELIBERATE NON-RETRIES: clear permanent failures are surfaced
  # immediately. We do NOT retry on e.g. AccessDenied / UnauthorizedOperation,
  # ClusterNotFoundException, InvalidParameter*, ValidationException,
  # NoSuchBucket, ExpiredToken, ResourceInitializationError from a bad image,
  # etc. Retrying those just wastes ~30s+ and hides the real cause.

  module_function

  # Drop-in for Open3.capture3(*cmd) with transient-failure retries.
  # Returns [stdout, stderr, status] -- the final attempt's tuple.
  #
  # Options (mostly for tests):
  #   max_attempts:, base_delay:, max_delay:, jitter:
  #   sleeper: ->(seconds) {}   # injectable sleep (tests pass a no-op)
  def capture3(*cmd, max_attempts: DEFAULT_MAX_ATTEMPTS,
               base_delay: DEFAULT_BASE_DELAY, max_delay: DEFAULT_MAX_DELAY,
               jitter: DEFAULT_JITTER, sleeper: nil)
    sleeper ||= ->(seconds) { sleep(seconds) }
    attempt = 0
    stdout = stderr = status = nil

    loop do
      attempt += 1
      stdout, stderr, status = Open3.capture3(*cmd)

      return [stdout, stderr, status] if status&.success?

      combined = "#{stderr}\n#{stdout}"
      last_attempt = attempt >= max_attempts

      unless retryable?(combined)
        # Permanent failure -- surface immediately, do not retry.
        log_permanent(cmd, attempt, stderr)
        return [stdout, stderr, status]
      end

      if last_attempt
        log_exhausted(cmd, attempt, stderr)
        return [stdout, stderr, status]
      end

      delay = backoff_delay(attempt, base_delay, max_delay, jitter)
      log_retry(cmd, attempt, max_attempts, delay, stderr)
      sleeper.call(delay)
    end
  end

  # True if the failure output matches a known transient/retryable signal.
  def retryable?(output)
    return false if output.nil?

    RETRYABLE_PATTERNS.any? { |pattern| output.match?(pattern) }
  end

  # Exponential backoff (base * 2^(attempt-1)) capped at max_delay, with +/- jitter.
  def backoff_delay(attempt, base_delay, max_delay, jitter)
    raw = base_delay * (2**(attempt - 1))
    capped = [raw, max_delay].min
    return capped if jitter.to_f <= 0

    spread = capped * jitter
    low = [capped - spread, 0.0].max
    high = capped + spread
    rand(low..high)
  end

  # --- logging (kept greppable so flakiness is visible in Sentry / logs) ---

  def stderr_snippet(stderr, limit = 500)
    return "" if stderr.nil?

    snippet = stderr.strip
    snippet.length > limit ? "#{snippet[0, limit]}..." : snippet
  end

  def log_retry(cmd, attempt, max_attempts, delay, stderr)
    Rails.logger.warn(
      "[AegeaRetry] transient failure on `#{cmd.first}` (attempt #{attempt}/#{max_attempts}); " \
      "retrying in #{delay.round(2)}s. stderr: #{stderr_snippet(stderr)}"
    )
  end

  def log_exhausted(cmd, attempt, stderr)
    Rails.logger.error(
      "[AegeaRetry] exhausted retries on `#{cmd.first}` after #{attempt} attempts. " \
      "Last stderr: #{stderr_snippet(stderr)}"
    )
  end

  def log_permanent(cmd, attempt, stderr)
    Rails.logger.error(
      "[AegeaRetry] permanent (non-retryable) failure on `#{cmd.first}` (attempt #{attempt}). " \
      "stderr: #{stderr_snippet(stderr)}"
    )
  end
end
