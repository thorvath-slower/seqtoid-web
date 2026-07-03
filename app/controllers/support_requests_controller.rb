# Lightweight sink for in-app self-help "Report an issue" submissions (Forgejo #440).
#
# Records a structured support request (diagnostics + optional user message) so that
# operators can correlate a user-reported problem with logs/metrics. This MVP records
# the request via the Rails structured logger and a Sentry breadcrumb/message; a full
# version would additionally fan the payload out to a ticketing system (Zendesk, etc.).
class SupportRequestsController < ApplicationController
  include ErrorHelper

  # authenticate_user! is already applied globally via ApplicationController, so this
  # endpoint is only reachable by a signed-in user. current_user is therefore present.
  def create
    request_params = support_request_params.to_h.deep_symbolize_keys

    record = {
      event: "support_request",
      user_id: current_user.id,
      user_email: current_user.email,
      user_role: current_user.role_name,
      description: request_params[:description].to_s.truncate(5000),
      diagnostics: sanitized_diagnostics(request_params[:diagnostics]),
      environment: Rails.env,
      git_release_sha: ENV["GIT_RELEASE_SHA"],
      submitted_at: Time.now.utc.iso8601,
    }

    # Structured log line is the durable, greppable record for operators, and
    # LogUtil.log_message forwards it to Sentry so it lands next to the user's
    # client-side errors.
    Rails.logger.info("[support_request] #{record.to_json}")
    LogUtil.log_message("Support request from user #{current_user.id}", **record)

    render json: { status: "ok" }, status: :created
  rescue StandardError => e
    LogUtil.log_error("Failed to record support request", exception: e)
    render json: { error: "Unable to record support request" }, status: :internal_server_error
  end

  private

  def support_request_params
    # diagnostics is a free-form client-collected object; permit it as an open hash.
    params.permit(:description, diagnostics: {})
  end

  # Guard against unbounded/huge diagnostics payloads being logged verbatim.
  def sanitized_diagnostics(diagnostics)
    return {} if diagnostics.blank?

    diagnostics.to_h.transform_values do |value|
      value.is_a?(String) ? value.truncate(2000) : value
    end
  end
end
