module Types
  # Federation mesh type
  # `query_fedWorkflowRunsAggregateTotalCount_aggregate_items` (CZID-285).
  class FedWorkflowRunsAggregateTotalCountItemType < Types::BaseObject
    graphql_name "query_fedWorkflowRunsAggregateTotalCount_aggregate_items"

    field :count, Int, null: true, camelize: false
    field :groupBy, Types::FedWorkflowRunsAggregateTotalCountGroupByType, null: true, camelize: false
  end
end
