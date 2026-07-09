require 'rails_helper'
require_relative '../../support/descartes_mock_server'

# CZID-601 -- the export_control:vc:test_screen operator diagnostic. Proves the creds-free NO-OP (no
# network) when the Descartes RPS environment is unset, and a clean run against the DescartesMockServer
# when it is configured -- WITHOUT writing any DB rows (the task calls the client directly).
describe 'export_control:vc:test_screen' do
  let(:task) { Rake::Task['export_control:vc:test_screen'] }

  before { HttpResilience.reset! }
  after { task.reenable }

  def run(*args)
    out = StringIO.new
    orig = $stdout
    $stdout = out
    task.invoke(*args)
    out.string
  ensure
    $stdout = orig
  end

  describe 'unset environment (no credentials)' do
    before do
      allow(ExportControl::Descartes::SearchEntityClient::Config).to receive(:from_env).and_return(
        ExportControl::Descartes::SearchEntityClient::Config.new(endpoint: nil, secno: nil, password: nil)
      )
    end

    it 'SKIPS with a clear message and makes NO network call, writing no rows' do
      output = nil
      expect { output = run('Wayne Smith', '', 'US') }
        .to change(ScreeningResult, :count).by(0).and(change(Hold, :count).by(0))
      expect(output).to include('SKIPPED')
      expect(WebMock).not_to have_requested(:post, /.*/)
    end
  end

  describe 'configured environment (against the mock)' do
    let(:mock) { DescartesMockServer.new }

    before do
      allow(ExportControl::Descartes::SearchEntityClient::Config).to receive(:from_env)
        .and_return(mock.search_config)
      mock.register_hit(name: 'Wayne Smith', smaxalert: '_R').install!
    end

    it 'runs a single screen and reports the parsed hit, persisting NOTHING' do
      output = nil
      expect { output = run('Wayne Smith', '', 'US') }
        .to change(ScreeningResult, :count).by(0).and(change(Hold, :count).by(0))
      expect(output).to include('transstatus')
      expect(output).to include('On Hold-RPS').or include('would HOLD')
      expect(output).to include('MOCKDIST001') # the sdistributedid poll-correlation key
    end
  end

  describe 'no subject provided' do
    before do
      allow(ExportControl::Descartes::SearchEntityClient::Config).to receive(:from_env)
        .and_return(DescartesMockServer.new.search_config)
    end

    it 'errors clearly and screens nothing' do
      expect(run('', '', '')).to include('provide a name or company')
    end
  end
end
