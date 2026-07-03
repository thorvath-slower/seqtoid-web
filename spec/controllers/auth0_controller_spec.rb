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
    it "does not register a /direct_user_login route in any environment" do
      expect do
        Rails.application.routes.recognize_path("/direct_user_login", method: :get)
      end.to raise_error(ActionController::RoutingError)
    end

    it "does not expose a direct_user_login controller action" do
      expect(Auth0Controller.action_methods).not_to include("direct_user_login")
    end

    it "does not expose a direct_login helper that sets the warden user" do
      expect(Auth0Helper.instance_methods).not_to include(:direct_login)
    end

    it "refuses to reach a login path for /direct_user_login (unrecognized route)" do
      # show_exceptions is :none in the test env, so an unrecognized route raises
      # rather than logging anyone in.
      expect do
        get "/direct_user_login", params: { user_id: @joe.id }
      end.to raise_error(ActionController::RoutingError)
    end

    # Explicit fail-closed guarantee for the environments that matter most.
    # The route was removed unconditionally (it is NOT wrapped in any
    # `if Rails.env.development?` block), so it is absent in every environment.
    # We assert that under a stubbed staging/production env the path is still
    # unrecognized -> the endpoint denies (no login) and cannot be reached.
    %w[production staging].each do |env_name|
      it "denies /direct_user_login when Rails.env is #{env_name} (fail closed)" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(env_name))
        expect(Rails.env.public_send("#{env_name}?")).to be(true)
        expect do
          Rails.application.routes.recognize_path("/direct_user_login", method: :get)
        end.to raise_error(ActionController::RoutingError)
      end
    end
  end
end
