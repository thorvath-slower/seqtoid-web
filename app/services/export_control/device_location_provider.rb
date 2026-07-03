# CZID-286 — the provider-agnostic device / location attestation-VERIFICATION contract (server-side).
# Mirrors the IDV + screening adapters. The endpoint + gate consume ONLY this interface.
#
# The SERVER's job here is to VERIFY a signed attestation token that the client obtained from the device-
# location vendor's SDK, and map the result onto DeviceLocationAttestation::STATUSES. GeoComply PinPoint
# is the reference shape (design doc CZID-329) — pluggable behind PROVIDER.
#
# ===== CLIENT SDK INTEGRATION POINT (HELD — TODO(vendor)) =====
# The client obtains the signed token by embedding the vendor's frontend SDK (e.g. GeoComply PinPoint web
# SDK). That frontend integration is VENDOR-SPECIFIC and is deliberately NOT built here — building
# speculative frontend against an unknown SDK would be waste (standing rule: HOLD the client SDK). When a
# vendor is chosen:
#   1. embed the vendor SDK on the client, collect the device-attestation token, and
#   2. POST it to DeviceLocationAttestationsController#create (the server endpoint authored in this PR),
#      which calls verify_token below.
# Until then this server-side verifier is the authored half; the client half is a documented stub.
# ==============================================================
#
# Contract — verify_token(token, ctx) returns a Result:
#   status:         one of DeviceLocationAttestation::STATUSES (verified/failed/pending)
#   failure_reason: a DeviceLocationAttestation::FAILURE_* when NOT verified (nil when verified)
#   provider:       the provider name, for the CZID-331 evidence record
#   attestation_ref, asserted_country: coarse evidence (NOT precise coordinates — TODO(counsel): privacy)
#
# FAIL-CLOSED: a nil/blank/expired/spoofed/malformed token, a bad signature, or any provider error MUST
# yield status "failed" (with a failure_reason) — never "verified". No allow-on-uncertainty.
module ExportControl
  module DeviceLocationProvider
    Result = Struct.new(:status, :failure_reason, :provider, :attestation_ref, :asserted_country,
                        keyword_init: true)

    # TODO(counsel/vendor): set to the chosen device-location vendor (GeoComply the leading candidate) once
    # its DPA + verification keys are in place. Committed placeholder = reference stub (fails closed).
    PROVIDER = "reference_stub".freeze

    module_function

    def verify_token(token, ctx = {})
      provider_module.verify_token(token, ctx)
    end

    def provider_module
      case PROVIDER
      when "geocomply" then Providers::Geocomply
      else
        Providers::DeviceReferenceStub
      end
    end
  end
end
