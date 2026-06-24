module Types
  # Federation mesh type
  # `query_fedWorkflowRunsAggregateTotalCount_aggregate_items_groupBy_workflowVersion_workflow`
  # (CZID-285).
  class FedWorkflowRunsAggregateTotalCountGroupByWorkflowVersionWorkflowType < Types::BaseObject
    graphql_name "query_fedWorkflowRunsAggregateTotalCount_aggregate_items_groupBy_workflowVersion_workflow"

    field :name, String, null: true, camelize: false
  end
end
