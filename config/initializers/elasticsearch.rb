# Flag to turn elasticsearch callbacks on or off for Project/Sample/Metadatum/User models
ELASTICSEARCH_ON = !Rails.env.test?

# Initialize elasticsearch client
config = {
  host: ENV['ES_ADDRESS'],
  transport_options: { request: { timeout: 200 } },
}
# Wrap the search client in a circuit breaker (#496) so a hung ES domain fast-fails
# the taxon/prefix search path instead of every request paying the 200s timeout.
# OpensearchCircuit.wrap is a no-op passthrough when disabled (OPENSEARCH_BREAKER_ENABLED=0).
#
# #544: skip wiring the live search client during `rails assets:precompile` (marked by the
# build-only ENV["ASSETS_PRECOMPILE"], set in the Dockerfile). Precompiling boots the full
# environment but never searches, so the OpensearchCircuit wrapper (app/lib) is not needed;
# skipping it keeps asset compilation independent of the search stack. ENV["ASSETS_PRECOMPILE"]
# is never set at runtime, so deployed behavior is unchanged.
Elasticsearch::Model.client = OpensearchCircuit.wrap(Elasticsearch::Client.new(config), name: :search_opensearch) unless Rails.env.test? || ENV["ASSETS_PRECOMPILE"]
