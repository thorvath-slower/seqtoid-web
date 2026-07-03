# Note (5/21/24): Leaving this task to explain how we populate the data for the taxon description sidebar
# but we no longer have the workflow that generates the taxid2description.json file.
# Load taxon descriptions
# rake load_taxon_descriptions['s3://idseq-samples-prod/yunfang/taxid2description.json']
# To run an individual taxon: rake load_taxon_descriptions['s3://idseq-developers/omar/taxid2descriptiontest/4.9/taxid2description.json']

desc "Loads taxon descriptions from S3 into database"
task :load_taxon_descriptions, [:taxon_desc_s3_path] => :environment do |_t, args|
  Rails.logger.info("running load_taxon_descriptions=#{args[:taxon_desc_s3_path]}")

  # Guard against a missing/blank S3 path arg. Without this,
  # download_file_with_retries(nil, ...) surfaces as
  # `TypeError: no implicit conversion of nil into String` (Forgejo #388).
  if args[:taxon_desc_s3_path].blank?
    abort("load_taxon_descriptions requires an S3 path, e.g. rake load_taxon_descriptions['s3://bucket/taxid2description.json']")
  end

  downloaded_json_path = PipelineRun.download_file_with_retries(args[:taxon_desc_s3_path],
                                                                '/app/tmp/taxid2desc',
                                                                3)
  if downloaded_json_path.blank?
    abort("Failed to download taxon descriptions from #{args[:taxon_desc_s3_path]}")
  end

  LOAD_CHUNK_SIZE = 200
  json_dict = JSON.parse(File.read(downloaded_json_path)) # UTF-8 encoding is by default
  values_list = []
  date = DateTime.now.in_time_zone
  ActiveRecord::Base.transaction do
    json_dict.each do |taxid, data|
      # Description may be nil for some taxa; coerce to "" so .encode doesn't raise
      # `TypeError: no implicit conversion of nil into String` (Forgejo #388).
      description = (data['description'] || '').encode('utf-8', 'binary', invalid: :replace, undef: :replace, replace: '')
      title = (data['title'] || '').encode('utf-8', 'binary', invalid: :replace, undef: :replace, replace: '')
      summary = (data['summary'] || '').encode('utf-8', 'binary', invalid: :replace, undef: :replace, replace: '')
      datum = [taxid.to_i, data['pageid'].to_i,
               description, title, summary, date, date,].map { |v| ActiveRecord::Base.connection.quote(v) }
      values_list << datum
      if values_list.size >= LOAD_CHUNK_SIZE
        ActiveRecord::Base.connection.execute <<-SQL
          REPLACE INTO taxon_descriptions (taxid, wikipedia_id, description, title, summary, created_at, updated_at) VALUES #{values_list.map { |values| "(#{values.join(',')})" }.join(', ')}
        SQL
        values_list = []
      end
    end
    ActiveRecord::Base.connection.execute <<-SQL
      REPLACE INTO taxon_descriptions (taxid, wikipedia_id, description, title, summary, created_at, updated_at) VALUES #{values_list.map { |values| "(#{values.join(',')})" }.join(', ')}
    SQL
  end
end
