namespace :taxon_lineage_slice do
  CURRENT_VERSION = "2024-02-06".freeze
  SLICE_NAME = "taxon_lineages_2024_slice.csv".freeze
  INDEXES_PREFIX = "ncbi-indexes-prod/#{CURRENT_VERSION}/index-generation-2".freeze
  TAXON_LINEAGE_FILE_KEY = "#{INDEXES_PREFIX}/#{SLICE_NAME}".freeze

  desc "Seed 2024 taxon lineage data"
  task import_data_from_s3: :environment do
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
    total_rows = CSV.parse(csv_data, headers: true).count # Count rows for progress tracking

    # Process the CSV in chunks to avoid memory issues
    CSV.parse(csv_data, headers: true) do |row|
      rows << row.to_h.transform_values(&:to_s)
      if rows.size >= chunk_size
        # Inserting in bulk for performance reasons
        # rubocop:disable Rails/SkipsModelValidations
        TaxonLineage.insert_all(rows)
        # rubocop:enable Rails/SkipsModelValidations
        rows.clear # Clear the array to free up memory and prepare for the next chunk
        counter += chunk_size
        puts "#{(counter.to_f / total_rows) * 100}% of rows imported"
      end
    end

    # Insert any remaining rows that didn't fill up the last chunk
    unless rows.empty?
      # rubocop:disable Rails/SkipsModelValidations
      TaxonLineage.insert_all(rows) unless rows.empty?
      # rubocop:enable Rails/SkipsModelValidations
      counter += rows.size
      puts "#{(counter.to_f / total_rows) * 100}% of rows imported"
    end
  end

  task remove_slice: :environment do
    puts "Removing #{CURRENT_VERSION} taxon lineage slice"
    TaxonLineage.where(version_end: CURRENT_VERSION).destroy_all
  end

  task create_taxon_lineage_slice_es_index: :environment do
    puts "Creating Elasticsearch index for #{CURRENT_VERSION} slice of TaxonLineage data"
    TaxonLineage.__elasticsearch__.create_index!(force: true)
    TaxonLineage.__elasticsearch__.import
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
    if TaxonLineage.exists?(version_start: CURRENT_VERSION)
      puts "Taxon lineage slice #{CURRENT_VERSION} already present; skipping import."
    else
      puts "Taxon lineage slice #{CURRENT_VERSION} not found; importing from S3."
      Rake::Task["taxon_lineage_slice:import_data_from_s3"].invoke
    end

    unless defined?(ELASTICSEARCH_ON) && ELASTICSEARCH_ON
      puts "Elasticsearch disabled (ELASTICSEARCH_ON is false); skipping index build."
      next
    end

    puts "Ensuring Elasticsearch index for the #{CURRENT_VERSION} slice is built."
    # create_index!(force: true) + import is idempotent: it (re)creates the index
    # and reloads documents from the DB, so it converges to the current data.
    Rake::Task["taxon_lineage_slice:create_taxon_lineage_slice_es_index"].invoke
    puts "Taxon lineage load complete."
  end

end
