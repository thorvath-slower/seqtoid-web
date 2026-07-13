require "rails_helper"

# Regression coverage for the Auth0 OmniAuth `audience` fix (Forgejo #384, ports jsims 95f2dbd98).
#
# Auth0 now serves login from a custom DNS domain (auth.<env>.seqtoid.org) that differs from the
# canonical tenant domain. Management API (/api/v2/) calls are only authorized when the login flow
# requests the correct `audience`, supplied via AUTH0_CLI_AUDIENCE. The initializer
# (config/initializers/auth0.rb) adds that audience to the OmniAuth `authorize_params`, but only
# when the env var is present -- so login is unchanged in any environment where the audience has
# not been provisioned yet (the ops half of the same change: chamber/SSM).
#
# This spec locks in that guarded selection logic so a future edit cannot silently drop the audience
# (which re-breaks the Management API) or, conversely, start sending a blank audience (which breaks
# login) in an un-provisioned environment.
RSpec.describe "config/initializers/auth0.rb audience selection" do
  # Mirror of the guarded expression built in the initializer. Kept identical to the source so the
  # test fails loudly if the initializer's logic diverges.
  def build_authorize_params
    params = { scope: 'openid email' }
    params[:audience] = ENV["AUTH0_CLI_AUDIENCE"] if ENV["AUTH0_CLI_AUDIENCE"].present?
    params
  end

  it "keeps the initializer and this spec in sync (source still guards audience on presence)" do
    source = Rails.root.join("config", "initializers", "auth0.rb").read
    expect(source).to include('auth0_authorize_params[:audience] = ENV["AUTH0_CLI_AUDIENCE"] if ENV["AUTH0_CLI_AUDIENCE"].present?')
    expect(source).to include("authorize_params: auth0_authorize_params")
  end

  context "when AUTH0_CLI_AUDIENCE is set" do
    around do |example|
      original = ENV["AUTH0_CLI_AUDIENCE"]
      ENV["AUTH0_CLI_AUDIENCE"] = "https://seqtoid-dev.us.auth0.com/api/v2/"
      example.run
    ensure
      ENV["AUTH0_CLI_AUDIENCE"] = original
    end

    it "requests that audience so Management API (/api/v2/) calls are authorized" do
      expect(build_authorize_params).to eq(
        scope: 'openid email',
        audience: "https://seqtoid-dev.us.auth0.com/api/v2/"
      )
    end
  end

  context "when AUTH0_CLI_AUDIENCE is not set (not yet provisioned)" do
    around do |example|
      original = ENV["AUTH0_CLI_AUDIENCE"]
      ENV.delete("AUTH0_CLI_AUDIENCE")
      example.run
    ensure
      ENV["AUTH0_CLI_AUDIENCE"] = original
    end

    it "omits the audience entirely so login is unchanged" do
      params = build_authorize_params
      expect(params).to eq(scope: 'openid email')
      expect(params).not_to have_key(:audience)
    end
  end

  context "when AUTH0_CLI_AUDIENCE is blank" do
    around do |example|
      original = ENV["AUTH0_CLI_AUDIENCE"]
      ENV["AUTH0_CLI_AUDIENCE"] = ""
      example.run
    ensure
      ENV["AUTH0_CLI_AUDIENCE"] = original
    end

    it "does not send a blank audience (which would break login)" do
      params = build_authorize_params
      expect(params).not_to have_key(:audience)
    end
  end
end
