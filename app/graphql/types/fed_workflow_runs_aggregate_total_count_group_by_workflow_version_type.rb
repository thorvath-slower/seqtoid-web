module Types
  # Federation mesh type
  # `query_fedWorkflowRunsAggregateTotalCount_aggregate_items_groupBy_workflowVersion`
  # (CZID-285).
  class FedWorkflowRunsAggregateTotalCountGroupByWorkflowVersionType < Types::BaseObject
    graphql_name "query_fedWorkflowRunsAggregateTotalCount_aggregate_items_groupBy_workflowVersion"

    field :workflow, Types::FedWorkflowRunsAggregateTotalCountGroupByWorkflowVersionWorkflowType, null: true, camelize: false
  end
end
