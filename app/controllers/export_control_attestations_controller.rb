# CZID-330 — the click-through export-control / Terms-of-Use attestation.
#
#   GET  new    → show the attestation click-through (the user attests they are not in / not acting for
#                 a blocked jurisdiction). TODO(counsel): the copy is counsel-owned.
#   POST create → record the user's decision (accepted/declined) as an append-only evidence row, then
#                 send them onward (accepted → app) or to the deny page (declined).
#   GET  denied → the non-bypassable deny UX shown to a user whose latest decision is "declined".
#
# This controller is EXEMPT from the attestation gate (see ExportControlAttestationGate) — otherwise the
# gate would redirect-loop and the user could never attest. It still requires authentication.
class ExportControlAttestationsController < ApplicationController
  before_action :disable_header_navigation

  # Show the click-through. If the user is already cleared, don't nag them — send them home.
  def new
    if ExportControlAttestation.current_attestation_satisfied?(current_user)
      redirect_to root_path and return
    end

    @attestation_version = ExportControlAttestation::CURRENT_VERSION
    @show_blank_header = true
    render :new
  end

  # Record the decision. ALWAYS persist a row (accepted OR declined) — the decline is itself compliance
  # evidence (design doc §6). The record captures user, timestamp (created_at), IP, version, user agent.
  def create
    decision = params[:decision] == ExportControlAttestation::DECISION_ACCEPTED ? ExportControlAttestation::DECISION_ACCEPTED : ExportControlAttestation::DECISION_DECLINED

    ExportControlAttestation.create!(
      user: current_user,
      decision: decision,
      attestation_version: ExportControlAttestation::CURRENT_VERSION,
      ip_address: request.remote_ip,
      viewer_country: request.headers["CloudFront-Viewer-Country"],
      user_agent: request.user_agent&.slice(0, 1024)
    )

    if decision == ExportControlAttestation::DECISION_ACCEPTED
      redirect_to root_path
    else
      redirect_to export_control_denied_path
    end
  rescue ActiveRecord::RecordInvalid => e
    # Fail-closed: if we cannot record the attestation we do NOT let the user through. Send them back
    # to the form; the gate keeps them out until a valid accepted row exists.
    Rails.logger.error("[ExportControlAttestation] failed to record: #{e.message}")
    redirect_to new_export_control_attestation_path, alert: "We could not record your response. Please try again."
  end

  # The deny UX — clear, non-bypassable. Shown to a user whose latest decision is "declined". There is no
  # "continue anyway" affordance; the only paths out are to re-attest (accept) or to sign out.
  # TODO(counsel): the denial copy is counsel-owned.
  def denied
    @show_blank_header = true
    render :denied, status: :forbidden
  end
end
