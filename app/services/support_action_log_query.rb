# CZID-472 - Query side of the support-ticket enrichment backend.
#
# The OtelActionLogging concern (#472 capture side) emits an always-on structured
# log line for every key user action:
#
#   [user_action] {"czid.user_action.user_id":42,"action":"bulk_download.create","outcome":"error",...}
#
# Those lines are written UNCONDITIONALLY (not gated on OTLP export), so they land
# in CloudWatch Logs even when trace export is off. This service reads them back
# with a CloudWatch Logs Insights query and turns them into an ordered, human
# readable "what the user did, step by step" trail that the support enrichment
# payload attaches to a ticket (fills the action_log_steps hole in
# SupportRequestsController).
#
# Design constraints (mirrors the capture side):
#   - Inert + gated: does nothing and returns nil unless SUPPORT_LOG_GROUP is set,
#     so local/test/CI and any env without a configured log group stay silent and
#     behavior is unchanged.
#   - Never raises into the request path: any AWS / parsing failure is swallowed and
#     the caller gets nil. A best-effort enrichment must never break the support
#     submission itself.
#   - No PII by construction: it only reads back the identifiers the capture side
#     already recorded (user id, action, outcome, error class, request/trace id).
class SupportActionLogQuery
  # Marker every action-log line carries; used to scope the Insights query.
  ACTION_LOG_MARKER = "[user_action]".freeze

  # Bound the query so a support submission never hangs. CloudWatch Insights is
  # async: start_query returns an id, then we poll get_query_results until the
  # query reports Complete.
  DEFAULT_MAX_POLLS = 10
  DEFAULT_POLL_INTERVAL = 0.5
  DEFAULT_RESULT_LIMIT = 50

  # steps: the parsed, ordered action trail (nil when unavailable / not configured).
  def self.recent_steps(user_id:, correlation_id:, window_start:, window_end:, **opts)
    new(
      user_id: user_id,
      correlation_id: correlation_id,
      window_start: window_start,
      window_end: window_end,
      **opts
    ).recent_steps
  end

  def initialize(user_id:, correlation_id:, window_start:, window_end:,
                 log_group: nil, max_polls: DEFAULT_MAX_POLLS,
                 poll_interval: DEFAULT_POLL_INTERVAL, result_limit: DEFAULT_RESULT_LIMIT)
    @user_id = user_id
    @correlation_id = correlation_id.to_s
    @window_start = coerce_epoch(window_start)
    @window_end = coerce_epoch(window_end)
    @log_group = (log_group || ENV["SUPPORT_LOG_GROUP"]).presence
    @max_polls = max_polls
    @poll_interval = poll_interval
    @result_limit = result_limit
  end

  # Returns an array of step hashes (oldest first), or nil when the query cannot be
  # run (no log group configured) or fails. Never raises.
  def recent_steps
    return nil if @log_group.nil?
    return nil if @window_start.nil? || @window_end.nil?

    rows = run_query
    return nil if rows.nil?

    steps = rows.filter_map { |row| parse_row(row) }
    steps.sort_by { |s| s[:at].to_s }
  rescue StandardError => e
    Rails.logger.error("[support_action_log_query] failed for user #{@user_id}: #{e.class}: #{e.message}")
    nil
  end

  private

  # Runs the Insights query and returns the raw result rows (array of arrays of
  # {field:, value:} field objects), or nil if it did not complete.
  def run_query
    client = AwsClient[:cloudwatchlogs]
    query_id = client.start_query(
      log_group_name: @log_group,
      start_time: @window_start,
      end_time: @window_end,
      query_string: insights_query,
      limit: @result_limit
    ).query_id

    poll_results(client, query_id)
  end

  def poll_results(client, query_id)
    @max_polls.times do |attempt|
      resp = client.get_query_results(query_id: query_id)
      case resp.status
      when "Complete"
        return resp.results
      when "Failed", "Cancelled", "Timeout"
        Rails.logger.warn("[support_action_log_query] query #{query_id} ended #{resp.status}")
        return nil
      end
      # Still Running / Scheduled: wait before the next poll (skip after the last).
      sleep(@poll_interval) if attempt < @max_polls - 1
    end
    Rails.logger.warn("[support_action_log_query] query #{query_id} did not complete in #{@max_polls} polls")
    nil
  end

  # Scope to this user's action-log lines within the window. We match on the user
  # id and (belt-and-suspenders) the correlation id so a session-only line still
  # surfaces. Oldest-first so the trail reads chronologically.
  def insights_query
    <<~QUERY.squish
      fields @timestamp, @message
      | filter @message like "#{ACTION_LOG_MARKER}"
      | filter @message like /"czid.user_action.user_id":#{@user_id}/ or @message like /#{@correlation_id}/
      | sort @timestamp asc
      | limit #{@result_limit}
    QUERY
  end

  # Turn one Insights result row into a step hash. Each row is an array of field
  # objects with #field / #value; @message holds the raw log line whose JSON tail
  # we parse. Returns nil for rows that are not parseable action-log lines.
  def parse_row(row)
    fields = row.each_with_object({}) { |f, acc| acc[f.field] = f.value }
    message = fields["@message"].to_s
    return nil unless message.include?(ACTION_LOG_MARKER)

    payload = extract_payload(message)
    return nil if payload.nil?

    {
      at: fields["@timestamp"],
      action: payload["action"],
      outcome: payload["outcome"],
      error_class: payload["error_class"],
      controller: payload["czid.user_action.controller"],
      request_id: payload["czid.user_action.request_id"],
      trace_id: payload["czid.user_action.trace_id"],
    }.compact
  end

  # Parse the JSON object that follows the "[user_action] " marker. Nil on anything
  # that is not valid JSON, so a malformed line is skipped rather than fatal.
  def extract_payload(message)
    json_part = message.split(ACTION_LOG_MARKER, 2).last.to_s.strip
    return nil if json_part.empty?

    parsed = JSON.parse(json_part)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  # CloudWatch Logs Insights expects epoch seconds. Accept a Time, an ISO8601
  # string, or an integer and normalize.
  def coerce_epoch(value)
    case value
    when Integer then value
    when Time then value.to_i
    when String then Time.iso8601(value).to_i
    end
  rescue ArgumentError
    nil
  end
end
