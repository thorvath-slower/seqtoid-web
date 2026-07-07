require "zlib"
require "stringio"

namespace :taxon_lineage_slice do
  # Version + source file are ENV-overridable so an environment can load the FULL taxon
  # lineage (all ~3M rows) instead of the dev/test *slice*, WITHOUT a code change (Forgejo
  # #528 — the slice omits taxid 694009 and ~20k other taxa, surfacing as
  # TaxonLineage::LineageNotFoundError + taxon-indexing lambda failures). Defaults preserve
  # the historical slice behavior exactly; to switch an env to the full lineage, set in its
  # web-params:
  #   TAXON_LINEAGE_FILE_KEY = ncbi-indexes-prod/2024-02-06/index-generation-2/<full-lineage>.csv
  #   (optionally TAXON_LINEAGE_VERSION if the full file is a different lineage version)
  # then run the one-time replace: taxon_lineage_slice:remove_slice -> import_data_from_s3 ->
  # create_taxon_lineage_slice_es_index (rebuilds MySQL + OpenSearch from the full table).
  # See docs/TAXON-LINEAGE-FULL-CUTOVER.md.
  CURRENT_VERSION = (ENV["TAXON_LINEAGE_VERSION"].presence || "2024-02-06").freeze
  SLICE_NAME = "taxon_lineages_2024_slice.csv".freeze
  INDEXES_PREFIX = "ncbi-indexes-prod/#{CURRENT_VERSION}/index-generation-2".freeze
  TAXON_LINEAGE_FILE_KEY = (ENV["TAXON_LINEAGE_FILE_KEY"].presence || "#{INDEXES_PREFIX}/#{SLICE_NAME}").freeze

  # These are long-running offline jobs. Their DB connection can be dropped by the
  # server ("Server has gone away") between chunks, surfacing as
  # ActiveRecord::StatementInvalid / ConnectionNotEstablished (Forgejo #388).
  # Wrap the risky DB work so we reconnect once and retry before giving up.
  def self.with_db_reconnect(context, max_retries: 2)
    attempts = 0
    begin
      yield
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => exception
      attempts += 1
      raise if attempts > max_retries

      puts "DB connection lost during #{context} (#{exception.class}: #{exception.message}); reconnecting (attempt #{attempts}/#{max_retries})."
      ActiveRecord::Base.connection.reconnect!
      retry
    end
  end

  desc "Seed 2024 taxon lineage data"
  task import_data_from_s3: :environment do
    # Long-running S3 import: on deploy/rollout the pod may be sent SIGTERM. Trap it
    # so we exit cleanly instead of raising `SignalException: SIGTERM` to Sentry
    # (Forgejo #388). The job is idempotent (guarded by the exists? check) and safe
    # to re-run on the next deploy.
    trap('SIGTERM') do
      puts "Received SIGTERM; aborting taxon lineage import cleanly (safe to re-run)."
      exit(0)
    end

    puts "Inserting #{CURRENT_VERSION} taxon lineage slice, this could take a while"

    if TaxonLineage.exists?(version_start: CURRENT_VERSION)
      abort("Taxon Lineage data for #{CURRENT_VERSION} already exists")
    end

    print "Connecting to Taxon Lineage S3 bucket [#{S3_DATABASE_BUCKET}] key [#{TAXON_LINEAGE_FILE_KEY}]"
    s3 = Aws::S3::Client.new
    response = s3.get_object(bucket: S3_DATABASE_BUCKET, key: TAXON_LINEAGE_FILE_KEY)
    print "Importing Taxon Lineage data from S3"

    chunk_size = 10_000
    rows = []
    counter = 0

    csv_data = response.body.read # Read the data once
    # The FULL lineage export (versioned-taxid-lineages.csv.gz, #528) is gzipped; the dev
    # slice is plain CSV. Transparently gunzip when the key is .gz so the same loader serves
    # both. (Whole-file in memory, as before — size the taxon-load Job's memory for the full
    # ~GB uncompressed set.)
    csv_data = Zlib::GzipReader.new(StringIO.new(csv_data)).read if TAXON_LINEAGE_FILE_KEY.end_with?(".gz")
    total_rows = CSV.parse(csv_data, headers: true).count # Count rows for progress tracking

    # Process the CSV in chunks to avoid memory issues
    CSV.parse(csv_data, headers: true) do |row|
      rows << row.to_h.transform_values(&:to_s)
      if rows.size >= chunk_size
        # Inserting in bulk for performance reasons
        # rubocop:disable Rails/SkipsModelValidations
        with_db_reconnect("taxon lineage chunk insert") { TaxonLineage.insert_all(rows) }
        # rubocop:enable Rails/SkipsModelValidations
        rows.clear # Clear the array to free up memory and prepare for the next chunk
        counter += chunk_size
        puts "#{(counter.to_f / total_rows) * 100}% of rows imported"
      end
    end

    # Insert any remaining rows that didn't fill up the last chunk
    unless rows.empty?
      # rubocop:disable Rails/SkipsModelValidations
      with_db_reconnect("taxon lineage final chunk insert") { TaxonLineage.insert_all(rows) }
      # rubocop:enable Rails/SkipsModelValidations
      counter += rows.size
      puts "#{(counter.to_f / total_rows) * 100}% of rows imported"
    end
  end

  task remove_slice: :environment do
    puts "Removing #{CURRENT_VERSION} taxon lineage slice"
    # destroy_all on a large slice can outlive the DB connection ("Server has gone
    # away"); reconnect+retry instead of raising ActiveRecord::StatementInvalid
    # (Forgejo #388).
    with_db_reconnect("remove_slice") do
      TaxonLineage.where(version_end: CURRENT_VERSION).destroy_all
    end
  end

  task create_taxon_lineage_slice_es_index: :environment do
    puts "Creating Elasticsearch index for #{CURRENT_VERSION} slice of TaxonLineage data"
    es = TaxonLineage.__elasticsearch__
    es.create_index!(force: true)

    # Bulk-load tuning (#477): during the import, disable per-batch refresh and drop
    # replicas so OpenSearch spends its I/O on ingest, not on refreshing segments and
    # replicating every doc. Capture the index's original settings first and restore
    # them in an `ensure` (so a failed import can't leave the index un-refreshed or
    # under-replicated). Larger `batch_size` = fewer, bigger `_bulk` requests.
    index = es.index_name
    current = es.client.indices.get_settings(index: index).values.first["settings"]["index"]
    restore = {
      refresh_interval: current["refresh_interval"] || "1s",
      number_of_replicas: current["number_of_replicas"] || "1",
    }
    puts "Bulk-load tuning: refresh_interval=-1, number_of_replicas=0 during import; restoring #{restore} after."
    es.client.indices.put_settings(index: index, body: { index: { refresh_interval: -1, number_of_replicas: 0 } })
    begin
      es.import(batch_size: 5000, refresh: false)
    ensure
      es.client.indices.put_settings(index: index, body: { index: restore })
      es.client.indices.refresh(index: index)
    end
    puts "Finished indexing TaxonLineage."
  end

  task remove_taxon_lineage_slice_es_index: :environment do
    puts "Removing Elasticsearch index for #{CURRENT_VERSION} slice of TaxonLineage data"
    TaxonLineage.__elasticsearch__.delete_index!
    puts "Finished removing TaxonLineage index"
  end

  # Idempotent, deploy-safe loader used by the Helm taxon-load Job (ticket #471).
  # A fresh deploy has no taxon lineage data, which breaks reports/taxonomy/heatmaps.
  # This runs at deploy time (PreSync hook, after db:migrate) and:
  #   * imports the taxon lineage slice from S3 ONLY if it isn't already loaded, and
  #   * (re)builds the OpenSearch/ES index so it matches the loaded data.
  # Unlike import_data_from_s3, it NEVER aborts/non-zeros when data already exists,
  # so re-running on every deploy is a no-op instead of a failed Job. It is safe to
  # run before web/workers come up.
  desc "Idempotently load the taxon lineage slice + build its ES index (deploy hook)"
  task load_slice_if_needed: :environment do
    # Completeness guard (#528, Issue 2). The old presence-only `exists?` check skipped
    # re-import once ANY row for the version existed, so a partial/truncated import (e.g. a
    # pod SIGTERM'd mid-load) was permanently masked — taxid 694009 went missing on dev for
    # exactly this reason. When TAXON_LINEAGE_MIN_ROWS is set (recommended: the source row
    # count for the full lineage), require the loaded count to meet it; a short load is
    # treated as incomplete, its rows cleared, and re-imported. Falls back to presence-only
    # when unset, so existing envs are unchanged until they opt in.
    min_rows = ENV["TAXON_LINEAGE_MIN_ROWS"].to_i
    loaded = TaxonLineage.where(version_start: CURRENT_VERSION).count
    complete = min_rows.positive? ? (loaded >= min_rows) : loaded.positive?
    if complete
      puts "Taxon lineage #{CURRENT_VERSION} present with #{loaded} rows#{min_rows.positive? ? " (>= #{min_rows})" : ''}; skipping import."
    else
      puts "Taxon lineage #{CURRENT_VERSION} missing or incomplete (#{loaded} rows#{min_rows.positive? ? " < #{min_rows}" : ''}); importing from S3."
      # A partial prior load leaves rows that would collide with the fresh import; clear them first.
      Rake::Task["taxon_lineage_slice:remove_slice"].invoke if loaded.positive?
      Rake::Task["taxon_lineage_slice:import_data_from_s3"].invoke
    end

    unless defined?(ELASTICSEARCH_ON) && ELASTICSEARCH_ON
      puts "Elasticsearch disabled (ELASTICSEARCH_ON is false); skipping index build."
      next
    end

    # Guard the (~53 min) ES rebuild (#476). This runs as an Argo PreSync hook on
    # EVERY deploy; the old code unconditionally called create_index!(force: true) +
    # a full re-import, which DROPS the index first — so taxonomy/heatmap were degraded
    # for the whole rebuild on every single deploy. Only (re)build when the index is
    # missing or its doc-count is out of sync with the DB. On ANY check error we fall
    # through to a rebuild — the safe default (never leaves a stale or missing index).
    es = TaxonLineage.__elasticsearch__
    db_count = TaxonLineage.count
    in_sync =
      begin
        es.client.indices.exists?(index: es.index_name) &&
          es.client.count(index: es.index_name)["count"].to_i == db_count
      rescue StandardError => e
        puts "ES index sync-check failed (#{e.class}: #{e.message}); will rebuild to be safe."
        false
      end

    if in_sync
      puts "ES index #{es.index_name} already built and in sync with the DB (#{db_count} docs); skipping rebuild."
    else
      puts "ES index missing or out of sync with the DB; (re)building."
      Rake::Task["taxon_lineage_slice:create_taxon_lineage_slice_es_index"].invoke
    end
    puts "Taxon lineage load complete."
  end
end
