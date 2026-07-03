# CZID-285 — the provider-agnostic denied/restricted-party SCREENING contract (the swap point), mirroring
# the IDV adapter + the Layer-2 edge adapter. The gate + controller consume ONLY this interface.
#
# Screens the identity against denied/restricted-party lists — OFAC SDN, BIS Entity List / Denied Persons
# List, and any others counsel deems applicable. Pluggable vendors: Descartes, Refinitiv World-Check, or a
# sanctions-API — all behind this interface.
#
# TODO(counsel/vendor): the FINAL screening vendor, the applicable LISTS + their sourcing/refresh cadence,
# and the legally-correct response to a HIT are counsel-owned (design doc Layer 3; a hit is not merely a
# technical deny — it may carry reporting obligations). Engineering only records the outcome + fails closed.
#
# Contract — screen(user, ctx) returns a Result:
#   result:        one of ExportControlClearance::SCREENING_RESULTS (clear/hit/pending)
#   provider:      the provider name, for the CZID-331 evidence record
#   evidence_ref:  opaque vendor case/screen id — NOT raw list data
#
# FAIL-CLOSED: any provider error/timeout MUST surface as a raise or a non-"clear" result. A HIT and a
# PENDING both DENY. A provider must NEVER return "clear" on uncertainty.
module ExportControl
  module DeniedPartyScreeningProvider
    Result = Struct.new(:result, :provider, :evidence_ref, keyword_init: true)

    # TODO(counsel/vendor): set to the procurement-chosen screening vendor once its DPA + list access +
    # keys are in place. The committed placeholder is the reference stub (returns PENDING → deny).
    PROVIDER = "reference_stub".freeze

    module_function

    def screen(user, ctx = {})
      provider_module.screen(user, ctx)
    end

    def provider_module
      case PROVIDER
      when "descartes"    then Providers::Descartes
      when "world_check"  then Providers::WorldCheck
      # when "sanctions_api" → add the module when that vendor is chosen (TODO(vendor)).
      else
        Providers::ReferenceStub
      end
    end
  end
end
