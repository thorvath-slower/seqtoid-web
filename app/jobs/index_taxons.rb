require 'elasticsearch/model'

# Indexes records for elasticsearch record
class IndexTaxons
  extend InstrumentedJob
  # This job invokes the taxon-indexing Lambda + writes to OpenSearch, both of which
  # fail transiently (throttling, 429s, endpoint blips). Retry with backoff and
  # dead-letter on exhaustion so a heatmap-indexing failure is retried + visible
  # rather than silently dropped (#496).
  extend ResqueRetryWithDeadLetter

  @queue = :index_taxons
  def self.perform(background_id, pipeline_run_id)
    Rails.logger.info("Start taxon indexing for pipeline_run_id: #{pipeline_run_id}")
    ElasticsearchQueryHelper.call_taxon_indexing_lambda(background_id, [pipeline_run_id])
  end
end
