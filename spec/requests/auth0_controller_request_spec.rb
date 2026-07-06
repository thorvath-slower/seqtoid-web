require "rails_helper"

# Coverage Wave 2 -- Auth0Controller request specs.
#
# The pre-existing spec/controllers/auth0_controller_spec.rb already covers the
# login redirect, the logout signout URL, the successful callback (login counter),
# and the removed-backdoor / dev_login routing guards. This file fills the routed
# actions/branches (was 41% line coverage):
#   * refresh_token   -- mode filtering + prompt selection
#   * background_refresh -- both the "no token" default branch and the
#                           "active token" branch of #background_refresh_values
#   * request_password_reset -- account-found vs no-account branches
#   * callback        -- authenticated-but-missing-user and unauthenticated
#                        branches
#   * filter_value    -- unknown mode rejected
#
# The two non-routed actions (dev_login, only routed in development, and
# omniauth_failure, invoked as a Rack action from OmniAuth's on_failure hook) are
# covered in spec/controllers/auth0_controller_actions_spec.rb via an anonymous
# controller so route drawing stays example-scoped.
#
# See app/controllers/auth0_controller.rb.
RSpec.describe "Auth0 request", type: :request do
  create_users

  describe "GET /auth0/refresh_token" do
    it "sets prompt=login and renders for an unknown/blank mode (filter_value rejects it)" do
      get auth0_refresh_token_path, params: { mode: "not-a-real-mode" }

      expect(response).to have_http_status(:ok)
      # filter_value returns nil for a value not in SUPPORTED_MODES, so prompt is "login".
      expect(assigns(:mode)).to be_nil
      expect(assigns(:prompt)).to eq("login")
      expect(assigns(:connection)).to eq(Auth0Controller::AUTH0_CONNECTION_NAME)
    end

    it "sets prompt=login for the login mode" do
      get auth0_refresh_token_path, params: { mode: "login" }

      expect(response).to have_http_status(:ok)
      expect(assigns(:mode)).to eq("login")
      expect(assigns(:prompt)).to eq("login")
    end

    it "sets prompt=none for the expired mode" do
      get auth0_refresh_token_path, params: { mode: "expired" }

      expect(response).to have_http_status(:ok)
      expect(assigns(:mode)).to eq("expired")
      expect(assigns(:prompt)).to eq("none")
    end

    it "sets prompt=none for the background_refresh mode" do
      get auth0_refresh_token_path, params: { mode: "background_refresh" }

      expect(response).to have_http_status(:ok)
      expect(assigns(:prompt)).to eq("none")
    end
  end

  describe "GET /auth0/background_refresh" do
    it "renders the inactive/default branch when there is no decoded token" do
      # auth0_decode_auth_token returns NOT_AUTHENTICATED (no :auth_payload), so
      # #background_refresh_values takes the else branch: should_refresh/expired true.
      allow_any_instance_of(Auth0Helper).to receive(:auth0_decode_auth_token)
        .and_return(Auth0Helper::NOT_AUTHENTICATED)

      get auth0_background_refresh_path, params: { mode: "background_refresh" }

      expect(response).to have_http_status(:ok)
      values = assigns(:refresh_values)
      expect(values[:active]).to eq(false)
      expect(values[:should_refresh]).to eq(true)
      expect(values[:expired]).to eq(true)
      expect(values[:exp]).to eq(0)
      expect(values[:refresh_endpoint]).to eq("/auth0/refresh_token?mode=background_refresh")
    end

    it "computes refresh timing from an active token (the present-payload branch)" do
      now = Time.now.to_i
      exp = now + 1.hour.to_i
      iat = now - 1.hour.to_i
      allow_any_instance_of(Auth0Helper).to receive(:auth0_decode_auth_token)
        .and_return(authenticated: true, auth_payload: { "exp" => exp, "iat" => iat })
      # The view renders the active-branch <script> only when auth0_session is present.
      allow_any_instance_of(Auth0Helper).to receive(:auth0_session_present?).and_return(true)
      allow_any_instance_of(Auth0Helper).to receive(:auth0_session).and_return({ "id_token" => "x" })

      get auth0_background_refresh_path, params: { mode: "background_refresh" }

      expect(response).to have_http_status(:ok)
      values = assigns(:refresh_values)
      expect(values[:active]).to eq(true)
      expect(values[:exp]).to eq(exp)
      expect(values[:iat]).to eq(iat)
      expect(values[:lifespan]).to eq(exp - iat)
      # exp is in the future, so it is not yet expired.
      expect(values[:expired]).to eq(false)
    end

    it "defaults iat when the token payload omits it" do
      now = Time.now.to_i
      exp = now + 1.hour.to_i
      allow_any_instance_of(Auth0Helper).to receive(:auth0_decode_auth_token)
        .and_return(authenticated: true, auth_payload: { "exp" => exp })
      allow_any_instance_of(Auth0Helper).to receive(:auth0_session_present?).and_return(false)
      allow_any_instance_of(Auth0Helper).to receive(:auth0_session).and_return(nil)

      get auth0_background_refresh_path

      expect(response).to have_http_status(:ok)
      values = assigns(:refresh_values)
      # iat defaults to exp - MAX_TOKEN_REFRESH_IN_SECONDS when missing.
      expect(values[:iat]).to eq(exp - Auth0Controller::MAX_TOKEN_REFRESH_IN_SECONDS)
      expect(values[:active]).to eq(false)
    end
  end

  describe "POST /auth0/request_password_reset" do
    it "sends an Auth0 reset email and redirects to login when the account exists" do
      expect(Auth0UserManagementHelper).to receive(:send_auth0_password_reset_email).with(@joe.email)

      post auth0_request_password_reset_path, params: { user: { email: @joe.email } }

      expect(response).to redirect_to(auth0_login_url)
    end

    it "sends a no-account-found email (not a reset) for an unknown address" do
      mail = double("mail", deliver_now: true)
      expect(UserMailer).to receive(:no_account_found).with("nobody@example.com").and_return(mail)
      expect(Auth0UserManagementHelper).not_to receive(:send_auth0_password_reset_email)

      post auth0_request_password_reset_path, params: { user: { email: "nobody@example.com" } }

      expect(response).to redirect_to(auth0_login_url)
    end

    it "no-ops (no redirect body) when the email is blank" do
      expect(Auth0UserManagementHelper).not_to receive(:send_auth0_password_reset_email)
      expect(UserMailer).not_to receive(:no_account_found)

      post auth0_request_password_reset_path, params: { user: { email: "" } }

      # The action returns early before any redirect_to, so no redirect is issued.
      expect(response).not_to be_redirect
    end
  end

  describe "GET /auth/auth0/callback (callback failure branches)" do
    it "renders a bad_request when Auth0 authenticated but no matching user exists" do
      allow_any_instance_of(Auth0Helper).to receive(:auth0_authenticate_with_bearer_token).and_return(true)
      # current_user stays nil -> the "logged in on Auth0 but missing from db" branch.
      allow_any_instance_of(Auth0Controller).to receive(:current_user).and_return(nil)

      get "/auth/auth0/callback/"

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("does not exist on this server")
    end

    it "logs out (redirects to signout) when bearer-token authentication fails" do
      allow_any_instance_of(Auth0Helper).to receive(:auth0_authenticate_with_bearer_token).and_return(false)

      get "/auth/auth0/callback/"

      # logout redirects to the Auth0 signout URL.
      expect(response).to be_redirect
      expect(response.redirect_url).to include("/v2/logout")
    end
  end
end
