module Types
  # Federation mesh type `query_SampleMetadata_additional_info_summary_stats` (CZID-285):
  # the summary stats hash assembled by SamplesHelper#get_summary_stats.
  class SampleMetadataSummaryStatsType < Types::BaseObject
    graphql_name "query_SampleMetadata_additional_info_summary_stats"

    field :adjusted_remaining_reads, Int, null: true, camelize: false
    field :compression_ratio, Float, null: true, camelize: false
    field :qc_percent, Float, null: true, camelize: false
    field :percent_remaining, Float, null: true, camelize: false
    field :unmapped_reads, Int, null: true, camelize: false
    field :insert_size_mean, Types::JsonScalar, null: true, camelize: false
    field :insert_size_standard_deviation, Types::JsonScalar, null: true, camelize: false
    field :last_processed_at, String, null: true, camelize: false
    field :reads_after_bowtie2_ercc_filtered, Types::JsonScalar, null: true, camelize: false
    field :reads_after_fastp, Int, null: true, camelize: false
    field :reads_after_bowtie2_host_filtered, Int, null: true, camelize: false
    field :reads_after_hisat2_host_filtered, Int, null: true, camelize: false
    field :reads_after_czid_dedup, Int, null: true, camelize: false
  end
end
