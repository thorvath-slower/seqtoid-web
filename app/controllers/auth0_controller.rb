# frozen_string_literal: true

class Auth0Controller < ApplicationController
  skip_before_action :authenticate_user!, :verify_authenticity_token
  skip_before_action :check_for_maintenance, only: :background_refresh

  include Auth0Helper

  SUPPORTED_MODES = Set[
    "background_refresh", # Background token refresh in a hidden iframe
    "login", # Invoked during login callback
    "expired", # Invoked when the token in the application session is expired / invalid
    "reset_password", # Invoked after reseting password operation
  ].freeze

  MIN_TOKEN_REFRESH_IN_SECONDS = 60.seconds.to_i
  MAX_TOKEN_REFRESH_IN_SECONDS = (60.minutes / 1.second).to_i

  AUTH0_CONNECTION_NAME = ENV["AUTH0_CONNECTION"] || "Username-Password-Authentication"
  AUTH0_UNAUTHORIZED = "unauthorized"
  AUTH0_LOGIN_REQUIRED = "login_required"
  # Whitelist descriptions to prevent phishing attempts.
  ERROR_EXPLANATIONS = { password_expired: "Your password has expired. Please update it by clicking Forgot Password on the sign-in page.", default: "Sorry, something went wrong when signing in. Please try again." }.freeze

  def refresh_token
    @mode = filter_value(params["mode"], SUPPORTED_MODES)
    @prompt = ["expired", "background_refresh"].include?(@mode) ? "none" : "login"
    @connection = AUTH0_CONNECTION_NAME
    render :refresh_token, layout: false
  end

  def login
    # Redirecting to the refresh token forcing a login operation
    redirect_to url_for(
      action: :refresh_token,
      params: { mode: "login" }
    )
  end

  # CZID-280 (#237) -- local-development sign-in that does not require a live
  # Auth0 tenant. Lets a developer running `Rails.env.development?` sign in with
  # no Auth0 client_id configured (offline), so the home -> login -> upload flow
  # is reachable locally.
  #
  # SECURITY: This is NOT the removed /direct_user_login backdoor (CZID-319 /
  # #276). Two independent guarantees keep it inert in every deployed env:
  #   1. The route is defined ONLY inside `if Rails.env.development?` in
  #      config/routes.rb, so it is absent from the staging/production route
  #      table entirely (it cannot be reached there at all).
  #   2. This action re-checks `Rails.env.development?` at runtime and 404s
  #      otherwise, as defense-in-depth if the action is ever reached by other
  #      means. It refuses to run unless the env is truly development.
  # It also takes NO user_id parameter, so it cannot be used to "become any
  # user" -- it signs in a single fixed seeded dev user (see dev_login_user).
  DEV_LOGIN_EMAIL = ENV.fetch("DEV_LOGIN_EMAIL", "dev@czid.local")

  def dev_login
    # Fail closed: never run outside development, regardless of how we got here.
    return head(:not_found) unless Rails.env.development?

    user = dev_login_user
    if user.nil?
      render(
        plain: "dev_login: no seeded user found. Seed a user (e.g. #{DEV_LOGIN_EMAIL}) first.",
        status: :not_found
      ) and return
    end

    # Mirror the real Auth0 callback: place the user in the :auth0_user warden
    # scope (the scope ApplicationController#current_user reads from).
    warden.logout(:user)
    warden.set_user(user, scope: :auth0_user)
    redirect_to home_path
  end

  def logout
    auth0_invalidate_application_session
    redirect_to auth0_signout_url
  end

  def failure
    logout
  end

  # Handle omniauth errors coming from Auth0.
  def omniauth_failure
    # Error and error_description come from Auth0. Ex: unauthorized and password_expired.
    error_type = (params["error"] || "").to_sym
    error_code = (params["error_description"] || "").to_sym
    unless params["error"] && params["error_description"]
      LogUtil.log_error(
        "omniauth_failure called with missing error or error_description.",
        error_type: error_type,
        error_description: error_code
      )
    end

    if error_type.present? && error_type == AUTH0_LOGIN_REQUIRED.to_sym
      # Silent login is expired, we need to logout current user
      logout
    elsif error_type.present? && error_type == AUTH0_UNAUTHORIZED.to_sym
      # Display 'unauthorized' errors but go to `failure` endpoint for all others.
      @message = if ERROR_EXPLANATIONS.key?(error_code)
                   ERROR_EXPLANATIONS[error_code]
                 else
                   ERROR_EXPLANATIONS[:default]
                 end
      render :omniauth_failure
    else
      failure
    end
  end

  def background_refresh
    @mode = params["mode"]
    @refresh_values = background_refresh_values
    render :background_refresh, layout: false
  end

  def callback
    # Store the user token that came from Auth0 and the IdP
    # Auth0Helper#auth0_session
    bearer_token = request.env['omniauth.auth']&.credentials.to_h

    user_was_not_present = current_user.nil?

    authenticated = auth0_authenticate_with_bearer_token(bearer_token)
    if authenticated
      if current_user.nil?
        LogUtil.log_error("User logged in on Auth0 but entry is missing from database.")
        render(
          json: "\"Your account does not exist on this server. Please contact help@czid.org for assistance.\"",
          status: :bad_request
        ) and return
      end

      # https://github.com/omniauth/omniauth-oauth2/issues/31#issuecomment-23806447
      mode = filter_value(request.env['omniauth.params']['mode'], SUPPORTED_MODES)

      # Update login counters if this is a new login
      if (mode == "login") || user_was_not_present
        current_user.update_tracked_fields!(request)
      end

      case mode
      when "background_refresh"
        redirect_to action: :background_refresh
      when "login", "expired"
        redirect_to home_path
      when "reset_password"
        redirect_to root_path
      else
        redirect_to root_path
      end
    else
      logout
    end
  end

  def request_password_reset
    email = params.dig("user", "email")
    return if email.blank?

    user = User.find_by(email: email)
    if user
      Auth0UserManagementHelper.send_auth0_password_reset_email(email)
    else
      # If no account found, send an informative email to reduce confusion.
      # This is good security practice to avoid revealing account existence on
      # a public endpoint.
      UserMailer.no_account_found(email).deliver_now
    end
    redirect_to auth0_login_url
  end

  private

  # The single fixed user dev_login signs in. Prefers a conventional seeded dev
  # account (DEV_LOGIN_EMAIL), then falls back to the first admin, then the first
  # user -- so a fresh dev DB still works. Deliberately NOT parameterized by
  # user_id: dev_login cannot be pointed at an arbitrary account.
  def dev_login_user
    User.find_by(email: DEV_LOGIN_EMAIL) ||
      User.where(role: User::ROLE_ADMIN).order(:id).first ||
      User.order(:id).first
  end

  def filter_value(value, set_of_values)
    value if set_of_values.include?(value)
  end

  def background_refresh_values
    auth0_token = auth0_decode_auth_token
    if auth0_token && auth0_token[:auth_payload]
      exp = auth0_token[:auth_payload]["exp"]
      # "iat" is not a mandatory JWT field. Auth0 sends this field, but adding a default in case it is missing
      iat = auth0_token[:auth_payload]["iat"] || (exp - MAX_TOKEN_REFRESH_IN_SECONDS)
      lifespan = exp - iat
      expires_in = exp - Time.now.to_i
      # We want to preemptively refresh the token before it expires.
      # Half of lifespan or MAX_TOKEN_REFRESH_IN_SECONDS minutes, whatever is shorter.
      should_refresh_in = [expires_in - (lifespan / 2), MAX_TOKEN_REFRESH_IN_SECONDS].min
      should_refresh = should_refresh_in <= 0
      expired = expires_in <= 0
    else
      lifespan = 0
      should_refresh_in = 0
      should_refresh = true
      expired = true
    end

    # background_refresh.html.erb script will reload the page to check
    # if the authentication token is due to a refresh based on this `reload_wait_seconds` parameter.
    # Here we are adjusting this reload time to be at reasonable frequency.
    reload_wait_seconds = [[lifespan / 4, MAX_TOKEN_REFRESH_IN_SECONDS].min, MIN_TOKEN_REFRESH_IN_SECONDS].max

    {
      active: auth0_session.present?,
      exp: exp || 0,
      iat: iat || 0,
      lifespan: lifespan,
      expires_in: expires_in || 0,
      should_refresh_in: should_refresh_in || 0,
      should_refresh: should_refresh,
      expired: expired,
      refresh_endpoint: "/auth0/refresh_token?mode=background_refresh",
      reload_wait_seconds: reload_wait_seconds,
    }
  end
end
