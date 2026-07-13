# CZID-285 — reference IDV provider stub. Mirrors the Layer-2 edge reference provider (spur.mjs): a
# working skeleton behind the PROVIDER constant, NOT a committed vendor and NOT a live call.
#
# It performs NO network I/O (no live vendor calls — standing rule) and, critically, returns PENDING —
# never a synthetic "verified". That keeps the fail-closed gate DENYING until a real, DPA-backed vendor
# (Persona/Onfido/Jumio/Stripe Identity/ID.me) is wired in via a sibling provider module. A real module
# would: call the vendor with the user's inquiry, read back the verification decision, map it onto
# ExportControlClearance::VERIFICATION_STATUSES, and RAISE on any error/timeout (fail-closed).
#
# TODO(counsel/vendor): replace with the procurement-chosen vendor module + its DPA-approved data flow.
module ExportControl
  module Providers
    module ReferenceStub
      module_function

      # The IDV half of the contract. Returns PENDING so the gate denies (uncertainty == deny).
      def verify(_user, _ctx = {})
        ExportControl::IdentityVerificationProvider::Result.new(
          status: ExportControlClearance::VERIFICATION_PENDING,
          provider: "reference_stub",
          evidence_ref: nil
        )
      end

      # The screening half of the contract (DeniedPartyScreeningProvider). Returns PENDING → deny.
      def screen(_user, _ctx = {})
        ExportControl::DeniedPartyScreeningProvider::Result.new(
          result: ExportControlClearance::SCREENING_PENDING,
          provider: "reference_stub",
          evidence_ref: nil
        )
      end
    end
  end
end
