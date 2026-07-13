module Types
  # Federation mesh type
  # `query_fedWorkflowRunsAggregate_aggregate_items_groupBy_workflowVersion_workflow`
  # (CZID-285).
  class FedWorkflowRunsAggregateGroupByWorkflowVersionWorkflowType < Types::BaseObject
    graphql_name "query_fedWorkflowRunsAggregate_aggregate_items_groupBy_workflowVersion_workflow"

    field :name, String, null: true, camelize: false
  end
end
