require "rails_helper"
require "webmock/rspec"

RSpec.describe Auth0Controller, type: :request do
  create_users

  context "Anon User" do
    it "request to protected endpoint should fail if user is not logged in" do
      post projects_url, params: { project: { name: "New Project" } }
      expect(response).to redirect_to(new_user_session_url)
    end

    it "request to protected endpoint should fail if user has already logged out" do
      sign_in_auth0 @joe
      post destroy_user_session_path
      post projects_url, params: { project: { name: "New Project" } }
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  context "Signed in User" do
    before do
      sign_in @joe
    end

    it "should redirect user to auth0 login" do
      get new_user_session_path
      expect(response).to redirect_to(url_for(controller: :auth0, action: :refresh_token, params: { mode: "login" }, only_path: true))
    end

    it "should redirect user to auth0 log out url when logging out" do
      sign_in @joe
      post destroy_user_session_path
      expect("https://#{ENV['AUTH0_DOMAIN']}/v2/logout").to eq(response.redirect_url.split("?").first)
    end
  end

  context "Using auth0_management_client_double" do
    it "should increment login counter" do
      setup_auth0_double
      previous_count = User.find(@joe.id).sign_in_count
      sign_in_auth0 @joe
      new_count = User.find(@joe.id).sign_in_count
      expect(previous_count + 1).to eq(new_count)
    end
  end

  # Regression guard for the /direct_user_login auth-bypass backdoor (CZID-319 / Forgejo #276).
  #
  # `GET /direct_user_login?user_id=N` previously logged in as ANY user with no
  # password, no Auth0, and no environment gate. It was stripped entirely from the
  # production line (route + action + helper) rather than env-gated, so the router
  # must not recognize it in ANY environment. These specs fail loudly if the
  # backdoor is ever reintroduced.
  context "direct_user_login backdoor (must not exist)" do
    it "does not route /direct_user_login to the removed backdoor action" do
      # It can't raise RoutingError: the `get '/:id'` URL-shortener catch-all
      # (shortener/shortened_urls#show) claims any single path segment and simply
      # 404s a missing short-url. The real guarantee is that /direct_user_login
      # never reaches auth0#direct_user_login.
      route = Rails.application.routes.recognize_path("/direct_user_login", method: :get)
      expect(route).not_to include(controller: "auth0", action: "direct_user_login")
      expect(route[:controller]).not_to eq("auth0")
    end

    it "does not expose a direct_user_login controller action" do
      expect(Auth0Controller.action_methods).not_to include("direct_user_login")
    end

    it "does not expose a direct_login helper that sets the warden user" do
      expect(Auth0Helper.instance_methods).not_to include(:direct_login)
    end

    it "cannot reach the auth0 controller via /direct_user_login (no login path)" do
      # The path resolves to the harmless shortener, never auth0 -- so no request
      # can log a user in through the old backdoor.
      route = Rails.application.routes.recognize_path("/direct_user_login", method: :get)
      expect(route[:controller]).not_to eq("auth0")
    end

    # Routes are environment-independent (the backdoor was removed unconditionally,
    # not env-gated), so /direct_user_login never reaches the backdoor in any env.
    %w[production staging].each do |env_name|
      it "does not route /direct_user_login to the backdoor when Rails.env is #{env_name}" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(env_name))
        expect(Rails.env.public_send("#{env_name}?")).to be(true)
        route = Rails.application.routes.recognize_path("/direct_user_login", method: :get)
        expect(route).not_to include(controller: "auth0", action: "direct_user_login")
      end
    end
  end

  # Guard for the CZID-280 (#237) local-dev sign-in path (auth0#dev_login).
  #
  # The route is defined ONLY inside `if Rails.env.development?` in
  # config/routes.rb, so under any non-development boot (the test env here, and
  # every deployed env: staging/production) the dev-only route block never runs
  # and /auth0/dev_login is NOT registered at all. Unlike the single-segment
  # /direct_user_login (which the `get '/:id'` URL-shortener catch-all claims),
  # /auth0/dev_login is a two-segment path that no catch-all matches, so the
  # router raises a hard ActionController::RoutingError -- the strongest possible
  # proof of absence. These specs fail loudly if the route is ever registered
  # outside development.
  context "dev_login local-sign-in path (dev-only, must not be routable in deployed envs)" do
    it "has no /auth0/dev_login route when the app is not booted in development" do
      # The test env loaded routes with Rails.env.development? == false, so the
      # dev-only route block never ran and this path is entirely unregistered.
      expect(Rails.env.development?).to be(false)
      expect do
        Rails.application.routes.recognize_path("/auth0/dev_login", method: :get)
      end.to raise_error(ActionController::RoutingError)
    end

    it "does not expose a route helper for the dev-only login path outside development" do
      # The named helper only exists when the route is defined (development).
      expect(Rails.application.routes.url_helpers).not_to respond_to(:auth0_dev_login_path)
    end

    # Routes are fixed at boot from the boot-time env; asserting under simulated
    # production/staging confirms no code path re-registers the dev route there.
    %w[production staging].each do |env_name|
      it "has no /auth0/dev_login route when Rails.env is #{env_name}" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(env_name))
        expect(Rails.env.public_send("#{env_name}?")).to be(true)
        expect do
          Rails.application.routes.recognize_path("/auth0/dev_login", method: :get)
        end.to raise_error(ActionController::RoutingError)
      end
    end
  end
end
