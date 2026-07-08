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
Elasticsearch::Model.client = OpensearchCircuit.wrap(Elasticsearch::Client.new(config), name: :search_opensearch) unless Rails.env.test?
