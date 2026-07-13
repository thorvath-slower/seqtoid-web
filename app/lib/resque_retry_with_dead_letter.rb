# frozen_string_literal: true

require "resque-retry"

# ResqueRetryWithDeadLetter is a one-line mixin that gives a Resque job:
#   1. RETRY WITH EXPONENTIAL BACKOFF on transient failures (via resque-retry's
#      ExponentialBackoff plugin), and
#   2. DEAD-LETTERING once retries are exhausted -- the job is recorded to the
#      DeadLetterQueue (durable + Sentry alert) instead of quietly landing in the
#      shared failure list, so a failed pipeline result-load / index job is retried
#      and stays visible, not lost (#496, part of the #467 reliability epic).
#
# This packages the pattern HardDeleteObjects already hand-rolls (extend Retry +
# @retry_exceptions + give_up_callback) into a reusable, ENV-tunable default so
# other transient-dependency jobs get the same behavior without copy-paste.
#
# Usage:
#   class IndexTaxons
#     extend InstrumentedJob
#     extend ResqueRetryWithDeadLetter   # <- retry + DLQ with defaults
#     @queue = :index_taxons
#     def self.perform(...); ...; end
#   end
#
# Override defaults per-job AFTER extending:
#   configure_retry_with_dead_letter(backoff: [0, 30, 120], retry_exceptions: [MyTransientError])
#
# HEALTHY-PATH BEHAVIOR IS UNCHANGED: retry/backoff/dead-letter logic only runs when
# a job RAISES. A job that succeeds behaves exactly as before.
module ResqueRetryWithDeadLetter
  # Default backoff schedule in seconds: immediate, 30s, 2m, 10m -> 4 total attempts.
  # Tunable process-wide via WORKER_RETRY_BACKOFF (comma-separated seconds).
  DEFAULT_BACKOFF = [0, 30, 120, 600].freeze

  def self.default_backoff
    raw = ENV["WORKER_RETRY_BACKOFF"]
    return DEFAULT_BACKOFF if raw.nil? || raw.strip.empty?

    parsed = raw.split(",").map { |s| Integer(s.strip) }
    parsed.empty? ? DEFAULT_BACKOFF : parsed
  rescue ArgumentError
    DEFAULT_BACKOFF
  end

  # Wire up resque-retry when a job class does `extend ResqueRetryWithDeadLetter`.
  def self.extended(base)
    base.extend Resque::Plugins::ExponentialBackoff
    base.configure_retry_with_dead_letter
  end

  # (Re)configure the retry + dead-letter policy. Safe to call again to override
  # the defaults for a specific job.
  def configure_retry_with_dead_letter(backoff: nil, retry_exceptions: [StandardError])
    @backoff_strategy = backoff || ResqueRetryWithDeadLetter.default_backoff
    @retry_exceptions = retry_exceptions
    register_dead_letter_callback
  end

  # On give-up (all retries exhausted), record the job to the DeadLetterQueue.
  # `name` is resolved lazily inside the callback (its self/closure is the job
  # class when resque-retry runs it) rather than captured at extend time, when an
  # anonymous class would not yet have a name.
  def register_dead_letter_callback
    give_up_callback do |exception, *args|
      DeadLetterQueue.record(name, args, exception)
    end
  end
end
