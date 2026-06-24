module Types
  # Federation mesh type
  # `mutation_KickoffWGSWorkflow_items_parsed_cached_results_quality_metrics` (CZID-304).
  class KickoffWgsWorkflowItemQualityMetricsType < Types::BaseObject
    graphql_name "mutation_KickoffWGSWorkflow_items_parsed_cached_results_quality_metrics"

    field :total_reads, Int, null: true, camelize: false
    field :qc_percent, Float, null: true, camelize: false
    field :adjusted_remaining_reads, Int, null: true, camelize: false
    field :compression_ratio, Float, null: true, camelize: false
    field :total_ercc_reads, Int, null: true, camelize: false
    field :fraction_subsampled, Float, null: true, camelize: false
    field :insert_size_mean, Types::JsonScalar, null: true, camelize: false
    field :insert_size_standard_deviation, Types::JsonScalar, null: true, camelize: false
    field :percent_remaining, Float, null: true, camelize: false
  end
end
