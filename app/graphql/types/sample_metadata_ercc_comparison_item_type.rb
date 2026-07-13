module Types
  # Federation mesh type
  # `query_SampleMetadata_additional_info_ercc_comparison_items` (CZID-285): one row of
  # PipelineRun#compare_ercc_counts.
  class SampleMetadataErccComparisonItemType < Types::BaseObject
    graphql_name "query_SampleMetadata_additional_info_ercc_comparison_items"

    field :name, String, null: true, camelize: false
    field :actual, Int, null: true, camelize: false
    field :expected, Types::JsonScalar, null: true, camelize: false
  end
end
