# frozen_string_literal: true

# OpensearchCircuit puts a CIRCUIT BREAKER in front of the app's OpenSearch/ES
# client so a hung or flapping OpenSearch domain fast-fails instead of tying up a
# request/worker thread on every call (#496, part of the #467 reliability epic).
#
# WHY: the ES clients are configured with a 200s request timeout
# (see ElasticsearchQueryHelper and config/initializers/elasticsearch.rb). When the
# heatmap domain is down or overloaded, every heatmap/search request pays that full
# timeout before failing, and enough concurrent requests exhaust the Puma pool and
# stall the whole app. Once N consecutive calls fail, the breaker OPENS and the next
# calls raise HttpResilience::CircuitOpenError immediately (no 200s hang) until a
# reset window elapses and a single trial call is allowed through.
#
# This reuses the in-house HttpResilience::CircuitBreaker (the same breaker guarding
# Auth0/LocationIQ) rather than adding a new dependency -- one house style, one set
# of state-machine tests.
#
# HEALTHY-PATH BEHAVIOR IS UNCHANGED: while the circuit is closed, every call is
# passed straight through to the real client and its return value/exception is
# forwarded verbatim. The breaker only changes behavior once a dependency is clearly
# down (fast-fail) -- exactly what #496 asks for.
#
# Coverage note: this wraps DIRECT client operations (`search`, `msearch`, `bulk`,
# `count`, `index`, `update`, ...). Namespaced admin calls chained off `.indices` /
# `.cluster` (index create/drop/alias swaps, used by the offline rebuild rake tasks)
# are NOT latency-critical user paths and pass through unbrokered.
#
# Usage (see config/initializers/elasticsearch.rb and ElasticsearchQueryHelper):
#   ES_CLIENT = OpensearchCircuit.wrap(Elasticsearch::Client.new(config), name: :heatmap_opensearch)
class OpensearchCircuit
  # ENV-tunable breaker knobs with safe defaults. Defaults intentionally match
  # HttpResilience so behavior is predictable across the two breaker users.
  def self.failure_threshold
    Integer(ENV.fetch("OPENSEARCH_BREAKER_FAILURE_THRESHOLD", HttpResilience::DEFAULT_FAILURE_THRESHOLD))
  end

  def self.reset_timeout
    Integer(ENV.fetch("OPENSEARCH_BREAKER_RESET_TIMEOUT", HttpResilience::DEFAULT_RESET_TIMEOUT))
  end

  # Master switch. Set OPENSEARCH_BREAKER_ENABLED=0 to bypass the wrapper entirely
  # and return the raw client (behavior identical to before this shipped).
  def self.enabled?
    ENV.fetch("OPENSEARCH_BREAKER_ENABLED", "1") != "0"
  end

  # Wrap `client` in a breaker. Returns the raw client untouched when disabled or
  # when the client is nil (e.g. the test environment, where no client is built).
  def self.wrap(client, name: :opensearch)
    return client if client.nil? || !enabled?

    new(client, name: name)
  end

  def initialize(client, name: :opensearch)
    @client = client
    @breaker = HttpResilience.breaker(name, failure_threshold: self.class.failure_threshold, reset_timeout: self.class.reset_timeout)
  end

  # Forward every call to the wrapped client through the breaker. A successful call
  # closes/keeps-closed the circuit; a raised error is recorded and re-raised so the
  # caller's existing rescue logic still sees the real ES error. Once the failure
  # threshold is crossed, subsequent calls raise HttpResilience::CircuitOpenError
  # without touching the client.
  def method_missing(name, *args, **kwargs, &block)
    if @client.respond_to?(name)
      @breaker.run { @client.public_send(name, *args, **kwargs, &block) }
    else
      super
    end
  end

  def respond_to_missing?(name, include_private = false)
    @client.respond_to?(name, include_private) || super
  end
end
