module Types
  # Federation mesh type
  # `query_fedWorkflowRunsAggregateTotalCount_aggregate_items_groupBy` (CZID-285).
  class FedWorkflowRunsAggregateTotalCountGroupByType < Types::BaseObject
    graphql_name "query_fedWorkflowRunsAggregateTotalCount_aggregate_items_groupBy"

    field :workflowVersion, Types::FedWorkflowRunsAggregateTotalCountGroupByWorkflowVersionType, null: true, camelize: false
  end
end
