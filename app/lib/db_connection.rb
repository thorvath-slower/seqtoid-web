# frozen_string_literal: true

# DbConnection centralizes MySQL connection self-healing (#496, part of the #467
# reliability epic).
#
# WHY: long-idle Resque workers and long-running rake loops hit the classic
# "MySQL server has gone away" -- the server drops an idle connection (wait_timeout)
# and the next query on that pooled connection raises
# ActiveRecord::StatementInvalid / ConnectionNotEstablished, killing the job. Instead
# of dying, workers should verify/reconnect and self-heal.
#
# Two entry points:
#   * verify! -- ping the current connection and transparently reconnect if the
#     server dropped it. Cheap; safe to call before doing DB work (e.g. from a
#     Resque after_fork hook so every forked job starts on a live connection).
#   * with_reconnect(context) { ... } -- wrap a risky/long DB operation so a
#     mid-operation "gone away" triggers a reconnect + bounded retry rather than a
#     hard failure. This is the pattern taxon_lineage_slice.rake hand-rolled
#     (Forgejo #388/#528); it now delegates here so there is one implementation.
#
# HEALTHY-PATH BEHAVIOR IS UNCHANGED: verify! is a no-op ping when the connection is
# alive, and with_reconnect only retries on connection-loss exceptions.
module DbConnection
  # Connection-loss exceptions we reconnect + retry on. StatementInvalid wraps the
  # underlying Mysql2::Error("server has gone away") the adapter raises.
  RECONNECT_EXCEPTIONS = [
    ActiveRecord::StatementInvalid,
    ActiveRecord::ConnectionNotEstablished,
  ].freeze

  DEFAULT_MAX_RETRIES = 2

  module_function

  # Ensure the current AR connection is alive, reconnecting if the server dropped it.
  # Returns true on a live/revived connection; false if it could not be revived
  # (never raises -- callers treat a false as "try again later").
  def verify!
    ActiveRecord::Base.connection.verify!
    true
  rescue StandardError => e
    log_warn("[DbConnection] verify! failed (#{e.class}: #{e.message}); forcing reconnect")
    force_reconnect
  end

  # Run the block, reconnecting + retrying (bounded) if the DB connection is lost
  # mid-operation. Non-connection errors propagate immediately.
  def with_reconnect(context, max_retries: DEFAULT_MAX_RETRIES)
    attempts = 0
    begin
      yield
    rescue *RECONNECT_EXCEPTIONS => e
      attempts += 1
      raise if attempts > max_retries

      log_warn("[DbConnection] connection lost during #{context} (#{e.class}: #{e.message}); reconnecting (attempt #{attempts}/#{max_retries})")
      force_reconnect
      retry
    end
  end

  # Force a hard reconnect of the current connection. Returns true on success,
  # false otherwise (never raises).
  def force_reconnect
    ActiveRecord::Base.connection.reconnect!
    true
  rescue StandardError => e
    log_warn("[DbConnection] reconnect! failed (#{e.class}: #{e.message})")
    false
  end

  def log_warn(msg)
    if defined?(Rails) && Rails.logger
      Rails.logger.warn(msg)
    else
      warn(msg)
    end
  end
end
