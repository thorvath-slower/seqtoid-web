require "rails_helper"

# Focused guard for the sentry-raven -> sentry-ruby migration (CZID-154):
# the maintained SDK must be loaded and the capture API reachable so that
# LogUtil and ApplicationController keep reporting errors after the swap.
RSpec.describe "Sentry SDK", type: :model do
  it "loads the sentry-ruby SDK (not the EOL raven client)" do
    expect(defined?(Sentry)).to eq("constant")
    expect(defined?(Raven)).to be_nil
  end

  it "exposes the capture API used by LogUtil / ApplicationController" do
    expect(Sentry).to respond_to(:capture_exception)
    expect(Sentry).to respond_to(:capture_message)
    expect(Sentry).to respond_to(:set_user)
    expect(Sentry).to respond_to(:set_extras)
  end

  it "captures an exception through a stubbed transport without raising" do
    # Initialize a throwaway client with a test transport so no event leaves
    # the process; proves the init path + capture_exception are wired.
    Sentry.init do |config|
      config.dsn = "http://public@example.com/1"
      config.enabled_environments = %w[test]
      config.environment = "test"
      config.transport.transport_class = Sentry::DummyTransport
      config.traces_sample_rate = 0.0
    end

    expect do
      Sentry.capture_exception(StandardError.new("czid-154 smoke"))
    end.not_to raise_error
  ensure
    # Reset the hub so this throwaway client does not leak into other specs.
    Sentry.instance_variable_set(:@main_hub, nil) if Sentry.instance_variable_defined?(:@main_hub)
  end
end
