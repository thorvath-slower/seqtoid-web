module Types
  # Federation mesh type `mutation_KickoffWGSWorkflow_items_parsed_cached_results`
  # (CZID-304).
  class KickoffWgsWorkflowItemParsedCachedResultsType < Types::BaseObject
    graphql_name "mutation_KickoffWGSWorkflow_items_parsed_cached_results"

    field :quality_metrics, Types::KickoffWgsWorkflowItemQualityMetricsType, null: true, camelize: false
  end
end
