# Sink for in-app self-help "Report an issue" submissions (Forgejo #440).
#
# Two layers, by design:
#   (A) The END USER only ever sees a minimal quick report (error / task / project
#       / account) in the popup. That arrives here as params[:quick_report].
#   (B) SUPPORT SIDE (this controller) enriches the submission into a RICH,
#       operator-only payload that the user never sees: a session/trace
#       correlation id, a best-effort "what happened and why" summary, a matched
#       runbook, and deep-links into CloudWatch Logs + the OTel dashboard filtered
#       to this user/session and time window.
#
# The enriched payload is recorded via the structured log (durable, greppable) and
# LogUtil.log_message (Sentry), "to a point" -- no external ticketing yet.
class SupportRequestsController < ApplicationController
  include ErrorHelper

  # Starter runbook catalog: known error/route patterns -> a runbook doc path and
  # a short label. Seeded with the common beta failure modes. These are
  # placeholder paths; the real runbooks are tracked as a TODO.
  # TODO(#440): replace placeholder paths with the real runbook URLs once the
  # support runbook docs land.
  RUNBOOK_CATALOG = [
    {
      id: "bulk_download_failure",
      match: /bulk[\s_-]?download/i,
      label: "Bulk download failure",
      runbook: "https://runbooks.seqtoid.internal/bulk-download-failure", # TODO(#440): real path
    },
    {
      id: "upload_failure",
      match: /upload|s3|resumable/i,
      label: "Upload failure",
      runbook: "https://runbooks.seqtoid.internal/upload-failure", # TODO(#440): real path
    },
    {
      id: "auth_login_failure",
      match: /auth|login|sign[\s_-]?in|token|401|403|unauthorized/i,
      label: "Auth / login failure",
      runbook: "https://runbooks.seqtoid.internal/auth-login-failure", # TODO(#440): real path
    },
  ].freeze

  # authenticate_user! is already applied globally via ApplicationController, so this
  # endpoint is only reachable by a signed-in user. current_user is therefore present.
  def create
    request_params = support_request_params.to_h.deep_symbolize_keys
    quick_report = (request_params[:quick_report] || {}).to_h
    diagnostics = sanitized_diagnostics(request_params[:diagnostics])

    # A correlation id so OTel/CloudWatch logs for this exact session can be found.
    # Rails' per-request id is our best available session/trace handle today; fall
    # back to a generated UUID when the request id isn't populated.
    correlation_id = request.request_id.presence || SecureRandom.uuid

    now = Time.now.utc
    # Time window around the report, used to scope the log deep-links.
    window_start = (now - 30.minutes).iso8601
    window_end = now.iso8601

    error_text = quick_report[:errorName].to_s
    route_text = diagnostics[:route].to_s.presence || quick_report[:task].to_s

    # (B) The rich, operator-only support payload. NEVER rendered back to the user.
    support_payload = {
      event: "support_request",
      correlation_id: correlation_id,
      # Who
      user_id: current_user.id,
      user_email: current_user.email,
      user_role: current_user.role_name,
      account_name: quick_report[:accountName],
      # What the user saw (the minimal, user-facing quick report)
      error: quick_report[:errorName],
      task: quick_report[:task],
      project: quick_report[:project],
      description: request_params[:description].to_s.truncate(5000),
      # Best-effort narrative for the agent.
      summary: build_summary(quick_report, diagnostics),
      # Matched runbook (nil-safe; falls back to a generic entry).
      runbook: match_runbook(error_text, route_text),
      # Deep-links into the logs, filtered to this user/session + time window.
      log_links: build_log_links(
        correlation_id: correlation_id,
        user_id: current_user.id,
        window_start: window_start,
        window_end: window_end
      ),
      # TODO(#472): attach the parsed, per-user OTel action-log step-by-step here.
      # The live query that turns OTel spans into a human-readable "what the user
      # did, step by step" is a separate dependency (#472). Until it lands we ship
      # the correlation id + log deep-links above so an operator can pull the trail
      # manually; do NOT synthesize fake step data here.
      action_log_steps: nil, # TODO(#472): populate from the OTel action-log query.
      # Full browser/session diagnostics (support-only).
      diagnostics: diagnostics,
      environment: Rails.env,
      git_release_sha: ENV["GIT_RELEASE_SHA"],
      submitted_at: now.iso8601,
    }

    # Structured log line is the durable, greppable record for operators, and
    # LogUtil.log_message forwards it to Sentry so it lands next to the user's
    # client-side errors.
    Rails.logger.info("[support_request] #{support_payload.to_json}")
    LogUtil.log_message(
      "Support request from user #{current_user.id} (#{correlation_id})",
      **support_payload
    )

    render json: { status: "ok", correlation_id: correlation_id }, status: :created
  rescue StandardError => e
    LogUtil.log_error("Failed to record support request", exception: e)
    render json: { error: "Unable to record support request" }, status: :internal_server_error
  end

  private

  def support_request_params
    # quick_report and diagnostics are free-form client-collected objects; permit
    # them as open hashes.
    params.permit(
      :description,
      quick_report: {},
      diagnostics: {}
    )
  end

  # Guard against unbounded/huge diagnostics payloads being logged verbatim.
  def sanitized_diagnostics(diagnostics)
    return {} if diagnostics.blank?

    diagnostics.to_h.deep_symbolize_keys.transform_values do |value|
      value.is_a?(String) ? value.truncate(2000) : value
    end
  end

  # A best-effort, human-readable "what happened and why" line for the support
  # agent, assembled from the error + route + user-facing context. Not a guarantee
  # of root cause -- a starting hypothesis.
  def build_summary(quick_report, diagnostics)
    account = quick_report[:accountName].presence || "A user"
    task = quick_report[:task].presence || "the app"
    project = quick_report[:project].presence
    error = quick_report[:errorName].presence || "an unspecified problem"
    route = diagnostics[:route].presence

    parts = ["#{account} hit \"#{error}\" while on \"#{task}\""]
    parts << "in #{project}" if project && project != "Not in a project"
    parts << "(route: #{route})" if route
    "#{parts.join(' ')}."
  end

  # Matches the error/route against the starter runbook catalog. Falls back to a
  # generic "triage" entry so the agent always has a next step.
  def match_runbook(error_text, route_text)
    haystack = "#{error_text} #{route_text}"
    entry = RUNBOOK_CATALOG.find { |rb| haystack.match?(rb[:match]) }
    return entry.slice(:id, :label, :runbook) if entry

    {
      id: "generic_triage",
      label: "No specific runbook matched -- general triage",
      # TODO(#440): point at the general support triage runbook once it exists.
      runbook: "https://runbooks.seqtoid.internal/general-triage",
    }
  end

  # Constructs deep-links into CloudWatch Logs (Insights) and the OTel dashboard,
  # pre-filtered to this user/session and time window, so an operator can jump
  # straight to the relevant logs.
  #
  # The log-group and OTel base are read from ENV/config. When they're not set we
  # still emit the URL SHAPE with a clear TODO placeholder so the intent is
  # obvious in the recorded payload.
  def build_log_links(correlation_id:, user_id:, window_start:, window_end:)
    region = ENV["AWS_REGION"].presence || AwsUtil::AWS_REGION
    # TODO(#440): set SUPPORT_LOG_GROUP / OTEL_DASHBOARD_BASE_URL in the app config
    # for each environment so these links resolve to real destinations.
    log_group = ENV["SUPPORT_LOG_GROUP"].presence || "TODO-set-SUPPORT_LOG_GROUP"
    otel_base = ENV["OTEL_DASHBOARD_BASE_URL"].presence || "TODO-set-OTEL_DASHBOARD_BASE_URL"

    # CloudWatch Logs Insights query scoped to this correlation id / user.
    insights_query = <<~QUERY.squish
      fields @timestamp, @message
      | filter @message like /#{correlation_id}/ or @message like /"user_id":#{user_id}/
      | sort @timestamp desc
      | limit 200
    QUERY

    cloudwatch_insights_url =
      "https://#{region}.console.aws.amazon.com/cloudwatch/home?region=#{region}" \
      "#logsV2:logs-insights$3FqueryDetail$3D" \
      "~(source~(~'#{log_group})" \
      "~start~'#{window_start}~end~'#{window_end}" \
      "~query~'#{CGI.escape(insights_query)})"

    otel_dashboard_url =
      "#{otel_base}?correlationId=#{correlation_id}&userId=#{user_id}" \
      "&from=#{window_start}&to=#{window_end}"

    {
      cloudwatch_logs_insights: cloudwatch_insights_url,
      otel_dashboard: otel_dashboard_url,
      # TODO(#472): the live OTel per-user action-log query link/embed goes here.
      otel_action_log: nil,
      window: { start: window_start, end: window_end },
    }
  end
end
