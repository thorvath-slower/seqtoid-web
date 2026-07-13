require 'rails_helper'

RSpec::Matchers.define_negated_matcher :not_change, :change

# CZID-596 -- the Descartes provider-contract adapter. Load-bearing guarantee: it is DARK by default.
# The committed PROVIDER is "reference_stub" (so this module is never resolved on the default path), and
# on top of that Descartes screening is OFF by default -- so even if called directly with the flag off it
# returns PENDING (deny, fail-closed) and makes NO network call and writes NO rows.
RSpec.describe ExportControl::Providers::Descartes, type: :service do
  let(:user) { create(:user) }

  it 'is not the resolved provider by default (reference_stub is)' do
    expect(ExportControl::DeniedPartyScreeningProvider.provider_module)
      .to eq(ExportControl::Providers::ReferenceStub)
  end

  context 'when Descartes screening is OFF (default)' do
    it 'returns PENDING (deny) without screening -- no rows, no call' do
      expect(ExportControl::ScreeningService.new.enabled?).to be(false)

      result = nil
      expect { result = described_class.screen(user) }
        .to not_change(ScreeningResult, :count).and(not_change(Hold, :count))

      expect(result.result).to eq(ExportControlClearance::SCREENING_PENDING)
      expect(result.result).not_to eq(ExportControlClearance::SCREENING_CLEAR)
      expect(result.provider).to eq('descartes')
    end
  end
end
