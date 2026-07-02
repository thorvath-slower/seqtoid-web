# OpenTelemetry (#426) - vendor-neutral tracing for the web app and the Resque /
# Shoryuken workers. Spans are exported over OTLP to the in-cluster ADOT collector
# (cypherid-web-infra terraform/modules/otel-collector), which re-exports to the
# AWS-native backend (X-Ray / CloudWatch). The app stays OTLP-only so the backend can
# be swapped by editing the collector alone.
#
# This is a no-op unless OTEL_EXPORTER_OTLP_ENDPOINT is set (mirrors the Sentry
# initializer's DSN gate), so local dev, tests and CI are unaffected. The endpoint is
# injected per-env into the ECS task definitions and points at the collector's OTLP
# HTTP receiver, e.g. http://collector.<env>.otel.internal:4318.
if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/all"

  OpenTelemetry::SDK.configure do |c|
    # Override per process via OTEL_SERVICE_NAME (e.g. seqtoid-web / seqtoid-resque /
    # seqtoid-shoryuken) so web and worker traces are distinguishable.
    c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "seqtoid-web")
    c.resource = OpenTelemetry::SDK::Resources::Resource.create(
      OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => (ENV["RAILS_ENV"] || Rails.env)
    )
    # Auto-instrument whatever is loaded: Rack/Rails/ActiveRecord/Mysql2/Net::HTTP/
    # Faraday/AWS SDK/Redis/Resque/GraphQL. The OTLP exporter is selected automatically
    # from the bundled opentelemetry-exporter-otlp gem.
    c.use_all
  end

  # Shoryuken has no bundled OpenTelemetry instrumentation, so wrap message processing
  # in a CONSUMER span ourselves. The producer here is AWS Step Functions (via
  # EventBridge/SNS), not app code, so these are new root spans rather than a continued
  # trace - still gives per-message worker visibility (latency, errors).
  if defined?(Shoryuken)
    class OpenTelemetryShoryukenMiddleware
      def call(worker_instance, queue, _sqs_msg, _body)
        tracer = OpenTelemetry.tracer_provider.tracer("shoryuken")
        span_name = "#{worker_instance.class.name} process"
        attributes = {
          OpenTelemetry::SemanticConventions::Trace::MESSAGING_SYSTEM => "aws_sqs",
          OpenTelemetry::SemanticConventions::Trace::MESSAGING_DESTINATION => queue.to_s,
          OpenTelemetry::SemanticConventions::Trace::MESSAGING_OPERATION => "process",
        }
        tracer.in_span(span_name, attributes: attributes, kind: :consumer) do |span|
          yield
        rescue StandardError => e
          span.record_exception(e)
          span.status = OpenTelemetry::Trace::Status.error(e.message)
          raise
        end
      end
    end

    Shoryuken.configure_server do |config|
      config.server_middleware do |chain|
        chain.add OpenTelemetryShoryukenMiddleware
      end
    end
  end
end
