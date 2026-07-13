module Types
  # Federation mesh type `query_SampleMetadata_additional_info` (CZID-285): the
  # `additional_info` block of SamplesController#metadata.
  class SampleMetadataAdditionalInfoType < Types::BaseObject
    graphql_name "query_SampleMetadata_additional_info"

    field :name, String, null: true, camelize: false
    field :editable, Boolean, null: true, camelize: false
    field :host_genome_name, String, null: true, camelize: false
    field :host_genome_taxa_category, String, null: true, camelize: false
    field :upload_date, String, null: true, camelize: false
    field :project_name, String, null: true, camelize: false
    field :project_id, Int, null: true, camelize: false
    field :notes, String, null: true, camelize: false
    field :ercc_comparison,
          [Types::SampleMetadataErccComparisonItemType],
          null: true,
          camelize: false
    field :pipeline_run, Types::SampleMetadataPipelineRunType, null: true, camelize: false
    field :summary_stats, Types::SampleMetadataSummaryStatsType, null: true, camelize: false
  end
end
