require "rails_helper"

# Coverage Wave 2 -- the two Auth0Controller actions that have no ordinary route:
#   * dev_login       -- routed ONLY in development (config/routes.rb), so it
#                        cannot be reached from a request spec in the test env.
#   * omniauth_failure -- not routed at all; invoked as a Rack action from
#                        OmniAuth's on_failure hook (config/initializers/auth0.rb).
#
# Both are exercised through an anonymous subclass of Auth0Controller. Drawing a
# route on an anonymous controller (the repo's ExportControlLayer3Gate pattern)
# keeps the temporary route scoped to this spec -- it does NOT mutate the shared
# application route table.
RSpec.describe Auth0Controller, type: :controller do
  controller(Auth0Controller) do
    # Inherits dev_login and omniauth_failure from Auth0Controller.
  end

  before do
    routes.draw do
      get "dev_login" => "anonymous#dev_login"
      get "omniauth_failure" => "anonymous#omniauth_failure"
    end
    # logout -> auth0_signout_url defaults its arg to root_url, which the
    # anonymous route table does not define. Stub the URL so the logout branches
    # under test redirect to a stable, assertable Auth0 signout URL.
    allow_any_instance_of(Auth0Helper).to receive(:auth0_signout_url)
      .and_return("https://auth0.example.test/v2/logout")
  end

  describe "#dev_login (fail-closed outside development)" do
    it "returns 404 in the test environment (Rails.env.development? is false)" do
      get :dev_login

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "#omniauth_failure" do
    it "logs out (redirects to signout) when the error is login_required" do
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

    it "logs an error and renders the default message when error_description is missing" do
      expect(LogUtil).to receive(:log_error).with(
        "omniauth_failure called with missing error or error_description.",
        hash_including(:error_type, :error_description)
      )

      # error is present (unauthorized) but error_description is absent: the guard
      # logs, then the empty error_code is not whitelisted, so :default renders.
      get :omniauth_failure, params: { error: "unauthorized" }

      expect(response).to have_http_status(:ok)
      expect(assigns(:message)).to eq(Auth0Controller::ERROR_EXPLANATIONS[:default])
    end

    it "logs an error and routes to failure when the error type is entirely missing" do
      expect(LogUtil).to receive(:log_error).with(
        "omniauth_failure called with missing error or error_description.",
        hash_including(:error_type, :error_description)
      )

      get :omniauth_failure

      expect(response).to be_redirect
      expect(response.redirect_url).to include("/v2/logout")
    end
  end
end
