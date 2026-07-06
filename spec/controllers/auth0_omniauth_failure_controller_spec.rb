require "rails_helper"

# Coverage Wave 2 -- Auth0Controller#omniauth_failure.
#
# omniauth_failure has no entry in config/routes.rb: it is invoked as a Rack
# action from OmniAuth's on_failure hook
# (Auth0Controller.action(:omniauth_failure).call(env), see
# config/initializers/auth0.rb). A controller spec with a temporary route lets us
# exercise every branch of the error dispatch without wiring OmniAuth.
#
# Branches covered (see app/controllers/auth0_controller.rb):
#   * login_required   -> logout (redirect to Auth0 signout)
#   * unauthorized + known error_description  -> renders the whitelisted message
#   * unauthorized + unknown error_description -> renders the :default message
#   * any other error_type -> failure -> logout
#   * missing error / error_description -> LogUtil.log_error is called
RSpec.describe Auth0Controller, type: :controller do
  before do
    # omniauth_failure is not in the app route table; draw it just for these specs.
    routes.draw do
      get "omniauth_failure" => "auth0#omniauth_failure"
    end
  end

  describe "#omniauth_failure" do
    it "logs out when error is login_required (silent-login expired)" do
      get :omniauth_failure, params: { error: "login_required", error_description: "anything" }

      expect(response).to be_redirect
      expect(response.redirect_url).to include("/v2/logout")
    end

    it "renders the whitelisted explanation for a known unauthorized error_description" do
      get :omniauth_failure, params: { error: "unauthorized", error_description: "password_expired" }

      expect(response).to have_http_status(:ok)
      expect(assigns(:message)).to eq(Auth0Controller::ERROR_EXPLANATIONS[:password_expired])
    end

    it "falls back to the default explanation for an unknown unauthorized error_description" do
      get :omniauth_failure, params: { error: "unauthorized", error_description: "some_other_reason" }

      expect(response).to have_http_status(:ok)
      expect(assigns(:message)).to eq(Auth0Controller::ERROR_EXPLANATIONS[:default])
    end

    it "routes any other error type through failure -> logout" do
      get :omniauth_failure, params: { error: "access_denied", error_description: "nope" }

      expect(response).to be_redirect
      expect(response.redirect_url).to include("/v2/logout")
    end

    it "logs an error when error_description is missing" do
      expect(LogUtil).to receive(:log_error).with(
        "omniauth_failure called with missing error or error_description.",
        hash_including(:error_type, :error_description)
      )

      # error is "unauthorized" but error_description is absent: the guard logs,
      # then (error_type is still present == unauthorized) the empty error_code
      # is not whitelisted, so the :default explanation renders.
      get :omniauth_failure, params: { error: "unauthorized" }

      expect(response).to have_http_status(:ok)
      expect(assigns(:message)).to eq(Auth0Controller::ERROR_EXPLANATIONS[:default])
    end

    it "logs and routes to failure when error type is entirely missing" do
      expect(LogUtil).to receive(:log_error).with(
        "omniauth_failure called with missing error or error_description.",
        hash_including(:error_type, :error_description)
      )

      # No error and no error_description: guard logs, error_type is blank, so the
      # final else routes through failure -> logout.
      get :omniauth_failure

      expect(response).to be_redirect
      expect(response.redirect_url).to include("/v2/logout")
    end
  end
end
