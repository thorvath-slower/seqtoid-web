# CZID-601 (Export-control Layer 3 / #285) -- operator diagnostic to run ONE live Descartes SearchEntity
# screen against the configured (sandbox) RPS endpoint, once real credentials exist. This is NOT part of
# any request path and does NOT persist a screening_results / holds row -- it calls the client directly
# and prints the parsed transstatus / alert / correlation ids so an operator can confirm connectivity and
# credentials during onboarding (design doc #595, Section 7).
#
# CREDS-GATED / NO-OP WHEN UNSET: reads DESCARTES_RPS_ENDPOINT / DESCARTES_RPS_SECNO /
# DESCARTES_RPS_PASSWORD from the environment (Chamber/SSM at runtime -- never the repo). With any of
# them missing it prints a clear message and exits cleanly (no network call). Nothing here runs on the
# default path; an operator invokes it by hand.
#
# Usage:
#   bundle exec rake 'export_control:vc:test_screen[Wayne Smith,,US]'
#   NAME="Wayne Smith" COUNTRY=US bundle exec rake export_control:vc:test_screen
namespace :export_control do
  namespace :vc do
    desc 'Run one live Descartes SearchEntity screen against the configured sandbox (no-op if creds unset)'
    task :test_screen, [:name, :company, :country] => :environment do |_t, args|
      config = ExportControl::Descartes::SearchEntityClient::Config.from_env
      unless config.configured?
        puts '[export_control:vc:test_screen] SKIPPED: Descartes RPS credentials are not configured.'
        puts '  Set DESCARTES_RPS_ENDPOINT, DESCARTES_RPS_SECNO, and DESCARTES_RPS_PASSWORD ' \
             '(Chamber/SSM) to run a live sandbox screen. No network call was made.'
        next
      end

      name = args[:name].presence || ENV['NAME']
      company = args[:company].presence || ENV['COMPANY']
      country = args[:country].presence || ENV['COUNTRY']
      if name.blank? && company.blank?
        puts '[export_control:vc:test_screen] ERROR: provide a name or company to screen ' \
             '(rake args or NAME=/COMPANY= env).'
        next
      end

      subject = ExportControl::ScreeningService::Subject.new(
        subject_ref: 'rake:test_screen', subject_type: 'Diagnostic',
        name: name, company: company, country: country,
        soptionalid: '0' # diagnostic; not a table-keyed screen (no DB row is written)
      )

      puts "[export_control:vc:test_screen] screening name=#{name.inspect} company=#{company.inspect} " \
           "country=#{country.inspect} against #{config.endpoint} ..."
      begin
        response = ExportControl::Descartes::SearchEntityClient.new(config: config)
                   .search(subject, soptionalid: '0')
      rescue ExportControl::Descartes::SearchEntityClient::Error => e
        # Fail-closed everywhere else means HOLD; here (a diagnostic) we just report the failure clearly.
        puts "[export_control:vc:test_screen] FAILED (fail-closed -> would HOLD in production): " \
             "#{e.class}: #{e.message}"
        next
      end

      puts '[export_control:vc:test_screen] OK. Parsed response:'
      puts "  transstatus    : #{response.transstatus.inspect} " \
           "(#{response.transstatus == ScreeningResult::TRANSSTATUS_PASSED ? 'would ALLOW' : 'would HOLD'})"
      puts "  alert_level    : #{response.alert_level}"
      puts "  risk_country   : #{response.risk_country.inspect}"
      puts "  sdistributedid : #{response.sdistributedid.inspect} (poll correlation key)"
      puts "  list           : #{response.list.inspect}"
      puts "  errored?       : #{response.errored?}"
    end
  end
end
