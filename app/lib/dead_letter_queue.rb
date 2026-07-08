# frozen_string_literal: true

# DeadLetterQueue is the durable, visible landing spot for Resque jobs that have
# EXHAUSTED their retries (#496, part of the #467 reliability epic).
#
# WHY: without this, a transient failure in a pipeline result-load / monitor job
# either vanished (no retry, buried in the shared Resque failure list that
# ClearResqueFailureQueue prunes after 7 days) or was indistinguishable from a
# never-retried failure, with no alert. Dead-lettering records the exhausted job
# (class, args, error, timestamp) to a capped Redis list AND fires a LogUtil error
# (Sentry) so the failure is explicitly visible and greppable, not lost.
#
# This is a companion to ResqueRetryWithDeadLetter, which calls .record from its
# give_up_callback once resque-retry has run out of attempts.
#
# The list is capped (LTRIM) so it can never grow unbounded and crash Redis --
# same failure mode ClearResqueFailureQueue guards against for the failure queue.
module DeadLetterQueue
  # Redis list holding the most recent dead-lettered jobs (newest first).
  REDIS_KEY = "resque:dead_letter"
  # Hard cap on retained entries; oldest are trimmed off.
  MAX_ENTRIES = 1000

  module_function

  # Record an exhausted job. Never raises -- the give-up path must not blow up.
  def record(job_class, args, exception)
    entry = {
      "job" => job_class.to_s,
      "args" => safe_args(args),
      "error_class" => exception&.class&.name,
      "error" => exception&.message,
      "failed_at" => Time.now.utc.iso8601,
    }
    persist(entry)
    LogUtil.log_error(
      "[DeadLetter] #{job_class} exhausted retries and was dead-lettered",
      exception: exception || StandardError.new("dead-lettered"),
      dead_letter: entry
    )
    entry
  rescue StandardError => e
    # A failure to record must not mask the original job failure.
    warn_log("[DeadLetter] failed to record dead letter for #{job_class}: #{e.class}: #{e.message}")
    nil
  end

  # Most recent dead-letter entries (parsed), newest first.
  def entries(limit = 100)
    return [] unless redis_available?

    Resque.redis.lrange(REDIS_KEY, 0, limit - 1).map { |raw| JSON.parse(raw) }
  end

  def count
    return 0 unless redis_available?

    Resque.redis.llen(REDIS_KEY)
  end

  def clear
    Resque.redis.del(REDIS_KEY) if redis_available?
  end

  # --- internals ---

  def persist(entry)
    return unless redis_available?

    Resque.redis.lpush(REDIS_KEY, JSON.dump(entry))
    Resque.redis.ltrim(REDIS_KEY, 0, MAX_ENTRIES - 1)
  end

  # Best-effort JSON-safe rendering of job args (they are already JSON-serializable
  # Resque payloads, but guard against anything odd).
  def safe_args(args)
    JSON.parse(JSON.dump(args))
  rescue StandardError
    Array(args).map(&:to_s)
  end

  def redis_available?
    defined?(Resque) && Resque.respond_to?(:redis) && Resque.redis
  rescue StandardError
    false
  end

  def warn_log(msg)
    if defined?(Rails) && Rails.logger
      Rails.logger.error(msg)
    else
      warn(msg)
    end
  end
end
