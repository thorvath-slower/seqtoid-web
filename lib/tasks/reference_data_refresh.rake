# On-demand, parametrized refresh of taxon-lineage reference data + its Elasticsearch index,
# decoupled from a full web deploy (#334 / feature 20029).
#
# The legacy `taxon_lineage_slice:*` tasks hardcode the version ("2024-02-06") and S3 key, and historically
# ran only as part of the retired hand-edited destructive deploy script on every deploy. This task takes
# the version + S3 key as parameters so a
# reference-data update can be applied on demand (via the refresh-reference-data GitHub Action) without
# redeploying the web service.
#
# Usage (args):
#   rake 'reference_data:refresh[2024-02-06,ncbi-indexes-prod/2024-02-06/index-generation-2/taxon_lineages_2024_slice.csv]'
# Usage (env, for CI):
#   REFERENCE_DATA_VERSION=2024-02-06 REFERENCE_DATA_FILE_KEY=ncbi-indexes-prod/.../taxon_lineages_2024_slice.csv \
#     rake reference_data:refresh
#   REFERENCE_DATA_FORCE=1  -> re-import even if the version already exists
namespace :reference_data do
  desc "Refresh taxon-lineage reference data + ES index on demand (parametrized; decoupled from deploy)"
  task :refresh, [:version, :file_key] => :environment do |_t, args|
    version  = (args[:version]  || ENV["REFERENCE_DATA_VERSION"]).to_s.strip
    file_key = (args[:file_key] || ENV["REFERENCE_DATA_FILE_KEY"]).to_s.strip
    force    = ENV["REFERENCE_DATA_FORCE"] == "1"

    abort("reference_data:refresh requires a version (arg or REFERENCE_DATA_VERSION)") if version.blank?
    abort("reference_data:refresh requires a file_key (arg or REFERENCE_DATA_FILE_KEY)") if file_key.blank?

    if TaxonLineage.exists?(version_start: version) && !force
      puts "Taxon lineage #{version} already present; skipping import (set REFERENCE_DATA_FORCE=1 to re-import)."
    else
      puts "Importing taxon lineage slice #{version} from s3://#{S3_DATABASE_BUCKET}/#{file_key}"
      response = Aws::S3::Client.new.get_object(bucket: S3_DATABASE_BUCKET, key: file_key)
      csv_data = response.body.read
      total = CSV.parse(csv_data, headers: true).count
      chunk_size = 10_000
      rows = []
      counter = 0

      # Default blank created_at/updated_at (the full versioned export leaves some empty) —
      # both are NOT NULL and insert_all skips Rails' timestamp defaulting (#528).
      now_ts = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
      CSV.parse(csv_data, headers: true) do |row|
        h = row.to_h.transform_values(&:to_s)
        h["created_at"] = now_ts if h["created_at"].blank?
        h["updated_at"] = now_ts if h["updated_at"].blank?
        rows << h
        next if rows.size < chunk_size

        # rubocop:disable Rails/SkipsModelValidations
        TaxonLineage.insert_all(rows)
        # rubocop:enable Rails/SkipsModelValidations
        counter += rows.size
        rows.clear
        puts "#{((counter.to_f / total) * 100).round(1)}% imported"
      end

      unless rows.empty?
        # rubocop:disable Rails/SkipsModelValidations
        TaxonLineage.insert_all(rows)
        # rubocop:enable Rails/SkipsModelValidations
        counter += rows.size
      end
      puts "Imported #{counter} taxon lineage rows for #{version}."
    end

    # Rebuild the taxon_lineages ES index from the (now-current) table. Mirrors the proven
    # taxon_lineage_slice:create_taxon_lineage_slice_es_index behavior that runs on deploy today.
    # NOTE: create_index!(force: true) recreates the index in place — see the GitHub Action's notes
    # for the (follow-up) zero-downtime alias-swap enhancement.
    puts "Rebuilding TaxonLineage Elasticsearch index..."
    TaxonLineage.__elasticsearch__.create_index!(force: true)
    TaxonLineage.__elasticsearch__.import
    puts "reference_data:refresh complete for #{version}."
  end
end
