# frozen_string_literal: true

class LogUtil
  def self.log_error(message, exception: nil, **details)
    # TODO(tiago): [CH-13826] add json support
    Rails.logger.error({
      message: message,
      exception: exception&.message,
      backtrace: exception&.backtrace,
      details: details,
    }.to_json)
    if exception
      # Exceptions have a default level of "error".
      # sentry-ruby's capture_exception uses the exception's own message as the
      # event title and does not accept a `message:` option, so carry the caller's
      # message through as extra context to preserve raven's behavior.
      Sentry.capture_exception(
        exception,
        extra: details.merge(message: message)
      )
    end
  end

  # If you want to report a message rather than an exception you can use the log_message method.
  def self.log_message(message, **details)
    Sentry.capture_message(
      message,
      level: "info",
      extra: details
    )
  end
end
