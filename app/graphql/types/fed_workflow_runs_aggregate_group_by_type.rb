module Types
  # Federation mesh type `query_fedWorkflowRunsAggregate_aggregate_items_groupBy`
  # (CZID-285).
  class FedWorkflowRunsAggregateGroupByType < Types::BaseObject
    graphql_name "query_fedWorkflowRunsAggregate_aggregate_items_groupBy"

    field :collectionId, Int, null: true, camelize: false
    field :workflowVersion, Types::FedWorkflowRunsAggregateGroupByWorkflowVersionType, null: true, camelize: false
  end
end
