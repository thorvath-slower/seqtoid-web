require 'rails_helper'
require_relative '../../support/descartes_mock_server'

RSpec::Matchers.define_negated_matcher :not_change, :change

# CZID-601 -- end-to-end integration of the Descartes two-phase restricted-party flow against the
# creds-free DescartesMockServer (no live sandbox). Exercises the REAL SearchEntityClient (CZID-596) and
# ResolutionClient (CZID-598) over WebMock:
#
#   screen -> hit (On Hold-RPS) -> hold created -> poll (DS New) -> keep held
#          -> officer adjudicates -> poll -> release / keep-held per verdict
#
# Also asserts the OFF-by-default flag makes the whole flow a no-op.
RSpec.describe 'Descartes screen -> hold -> poll -> resolve flow', type: :integration do
  let(:mock) { DescartesMockServer.new }
  let(:service) { ExportControl::ScreeningService.new(client: mock.search_client) }

  def poll!
    job = ResolveScreeningHolds.new
    allow(job).to receive(:client).and_return(mock.resolution_client)
    job.run
  end

  def subject(ref:, name: nil, company: nil, soptionalid: nil)
    ExportControl::ScreeningService::Subject.new(
      subject_ref: ref, subject_type: 'User', name: name, company: company,
      country: 'US', soptionalid: soptionalid
    )
  end

  before do
    HttpResilience.reset!
    AppConfigHelper.set_app_config(AppConfig::ENABLE_DESCARTES_SCREENING, '1')
  end

  describe 'a hit that a compliance officer later CLEARS' do
    before do
      mock.register_hit(name: 'Wayne Smith', smaxalert: '_R').install!
    end

    it 'holds on the screen, keeps held while DS New, and releases once Cleared' do
      # Phase 1: screen -> HIT -> hold.
      outcome = service.screen_if_enabled(subject(ref: 'User:42', name: 'Wayne Smith', soptionalid: '42'))
      expect(outcome.decision).to eq(:held)
      sr = outcome.screening_result
      hold = outcome.hold
      expect(sr.transstatus).to eq(ScreeningResult::TRANSSTATUS_ON_HOLD)
      expect(sr.sdistributedid).to eq('MOCKDIST001')
      expect(hold).to be_active
      expect(hold.reason).to eq(Hold::REASON_SCREENING_HIT)

      # Phase 2a: poll while the IM record is still fresh (DS New) -> KEEP HELD, but stamp the incident.
      poll!
      expect(hold.reload).to be_active
      expect(sr.reload.incident_id).to eq('MOCKDIST001')

      # A human compliance officer clears the alert in Incident Manager.
      mock.adjudicate('MOCKDIST001', 'Cleared')

      # Phase 2b: poll again -> RELEASE.
      poll!
      expect(hold.reload).not_to be_active
      expect(hold.released_at).to be_present
    end
  end

  describe 'a hit adjudicated TRUE HIT (terminal deny)' do
    before { mock.register_hit(company: 'BadCorp', smaxalert: 'TR').install! }

    it 'stays held forever' do
      outcome = service.screen_if_enabled(subject(ref: 'User:7', company: 'BadCorp', soptionalid: '7'))
      hold = outcome.hold
      expect(hold).to be_active

      mock.adjudicate(outcome.screening_result.sdistributedid, 'True Hit')
      poll!
      expect(hold.reload).to be_active # terminal deny -- never released
    end
  end

  describe 'a clean party' do
    before { mock.install! } # no hit rules -> everything screens clean

    it 'is ALLOWED with no hold, and the poller has nothing to release' do
      outcome = service.screen_if_enabled(subject(ref: 'User:9', name: 'Jane Clean', soptionalid: '9'))
      expect(outcome.decision).to eq(:allowed)
      expect(outcome.hold).to be_nil

      expect { poll! }.to not_change(Hold, :count).and(not_change(ScreeningResult, :count))
    end
  end

  describe 'idempotent re-resolution' do
    before { mock.register_hit(name: 'Repeat Poll').install! }

    it 're-polling a Cleared verdict keeps the first release timestamp and does not error' do
      outcome = service.screen_if_enabled(subject(ref: 'User:11', name: 'Repeat Poll', soptionalid: '11'))
      hold = outcome.hold
      mock.adjudicate(outcome.screening_result.sdistributedid, 'False Hit')

      poll!
      first_released_at = hold.reload.released_at
      expect(first_released_at).to be_present

      poll!
      expect(hold.reload.released_at).to eq(first_released_at)
    end
  end

  describe 'OFF-by-default: the whole flow is a no-op' do
    before do
      AppConfigHelper.set_app_config(AppConfig::ENABLE_DESCARTES_SCREENING, '')
      mock.register_hit(name: 'Wayne Smith').install!
    end

    it 'screen_if_enabled returns nil (no rows) and the poller self-skips' do
      result = nil
      expect { result = service.screen_if_enabled(subject(ref: 'User:42', name: 'Wayne Smith', soptionalid: '42')) }
        .to not_change(ScreeningResult, :count).and(not_change(Hold, :count))
      expect(result).to be_nil

      # Even with a pre-existing hold, the disabled poller self-skips and never polls (no release).
      sr = create(:screening_result, :red, subject_ref: 'User:99', sdistributedid: 'MOCKDIST001')
      hold = create(:hold, subject_ref: 'User:99', screening_result: sr)

      expect { poll! }.not_to change { hold.reload.released_at }
      expect(hold.reload).to be_active
    end
  end
end
