module Types
  # Federation mesh type
  # `query_fedWorkflowRunsAggregate_aggregate_items_groupBy_workflowVersion` (CZID-285).
  class FedWorkflowRunsAggregateGroupByWorkflowVersionType < Types::BaseObject
    graphql_name "query_fedWorkflowRunsAggregate_aggregate_items_groupBy_workflowVersion"

    field :workflow, Types::FedWorkflowRunsAggregateGroupByWorkflowVersionWorkflowType, null: true, camelize: false
  end
end
