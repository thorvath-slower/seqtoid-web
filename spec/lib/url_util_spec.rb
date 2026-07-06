# frozen_string_literal: true

require "rails_helper"

RSpec.describe UrlUtil do
  describe ".absolute_base_url" do
    # We build the expected URL from the SAME action_mailer config the method reads,
    # rather than hardcoding a host, so this stays valid across environments.
    let(:mailer_options) do
      Rails.application.config.action_mailer.default_url_options || {}
    end

    it "assembles protocol://host[:port] from action_mailer default_url_options" do
      host = mailer_options[:host] || "example.test"
      port = mailer_options[:port]
      protocol = mailer_options[:protocol] ||
                 (Rails.application.config.force_ssl ? "https" : "http")

      allow(Rails.application.config.action_mailer).to receive(:default_url_options)
        .and_return(host: host, port: port, protocol: protocol)

      expected_port = port ? ":#{port}" : ""
      expect(UrlUtil.absolute_base_url).to eq("#{protocol}://#{host}#{expected_port}")
    end

    it "omits the port segment when no port is configured" do
      allow(Rails.application.config.action_mailer).to receive(:default_url_options)
        .and_return(host: "seqtoid.test", port: nil, protocol: "https")
      expect(UrlUtil.absolute_base_url).to eq("https://seqtoid.test")
    end

    it "includes the port segment when a port is configured" do
      allow(Rails.application.config.action_mailer).to receive(:default_url_options)
        .and_return(host: "seqtoid.test", port: 3000, protocol: "http")
      expect(UrlUtil.absolute_base_url).to eq("http://seqtoid.test:3000")
    end

    it "falls back to force_ssl to choose the protocol when none is given" do
      allow(Rails.application.config.action_mailer).to receive(:default_url_options)
        .and_return(host: "seqtoid.test", port: nil, protocol: nil)
      allow(Rails.application.config).to receive(:force_ssl).and_return(true)
      expect(UrlUtil.absolute_base_url).to eq("https://seqtoid.test")

      allow(Rails.application.config).to receive(:force_ssl).and_return(false)
      expect(UrlUtil.absolute_base_url).to eq("http://seqtoid.test")
    end
  end
end
