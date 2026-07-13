module Types
  # Federation mesh type `query_fedWorkflowRunsAggregate_aggregate_items` (CZID-285).
  class FedWorkflowRunsAggregateItemType < Types::BaseObject
    graphql_name "query_fedWorkflowRunsAggregate_aggregate_items"

    field :groupBy, Types::FedWorkflowRunsAggregateGroupByType, null: true, camelize: false
    field :count, Int, null: true, camelize: false
  end
end
