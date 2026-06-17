class ResqueMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    if env['PATH_INFO'].start_with?("/resque")
      handle_resque_request(env)
    else
      @app.call(env)
    end
  end

  def handle_resque_request(env)
    rack_request = Rack::Request.new(env)
    rack_session = rack_request.session

    handle_input(env, rack_session, rack_request)
    handle_output(env)
  end

  def handle_input(env, rack_session, rack_request)
    # Restrict allowed characters going to Resque server params.
    # update_param will modify the original 'env' object.
    rack_request.params.each do |k, v|
      # Don't rely on other sanitize methods that may miss HTML encoding.
      rack_request.update_param(k, v.gsub(/[^0-9A-Za-z_]/, '')) unless k == "_csrf"
    end

    # Verify every request except GET and HEAD
    unless rack_request.get? || rack_request.head?
      valid_token = false

      # Expect actions to use a form submit with a _csrf hidden field.
      form_params = env["rack.request.form_hash"] || {}
      if form_params.key?("_csrf")
        valid_token = csrf_controller(env).send(:valid_authenticity_token?, rack_session, form_params["_csrf"])
      end

      # Stop execution with invalid token
      unless valid_token
        raise ActionController::InvalidAuthenticityToken
      end
    end
  end

  # CSRF reference: https://medium.com/rubyinside/a-deep-dive-into-csrf-protection-in-rails-19fa0a42c0ef
  def handle_output(env)
    # Get regular application response
    status, headers, response = @app.call(env)

    # Add a _csrf token to all Resque UI forms
    if response.is_a?(Array) && response.present?
      doc = Nokogiri::HTML.parse(response[0])

      # Masked token varies on each request but is valid for the session.
      # Note: The original token can be computed from the masked token, so the masked token must still be securely transmitted.
      masked_token = csrf_controller(env).send(:masked_authenticity_token)
      form_nodes = doc.xpath("//form")
      form_nodes.each do |form|
        form.prepend_child("<input type=\"hidden\" name=\"_csrf\" value=\"#{masked_token}\"/>")
      end
      response = [doc.to_s]
    end

    [status, headers, response]
  end

  private

  # A controller instance bound to the current request, used only to reach the
  # RequestForgeryProtection helpers (valid_authenticity_token? /
  # masked_authenticity_token).
  #
  # Rails 7.1 changed those helpers to read the real CSRF token from the live
  # request via the configured storage strategy (the default SessionStore reads
  # request.session[:_csrf_token]) instead of from a session passed as an
  # argument; masked_authenticity_token also dropped its positional session arg.
  # A detached ActionController::Base.new therefore raises (request is nil), so
  # we bind a fresh controller to an ActionDispatch::Request built from the rack
  # env. A new instance per call keeps this thread-safe.
  def csrf_controller(env)
    controller = ActionController::Base.new
    controller.set_request!(ActionDispatch::Request.new(env))
    controller
  end
end
