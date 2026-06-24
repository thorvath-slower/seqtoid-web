module Types
  # Federation mesh type `query_fedWorkflowRuns_items_workflowVersion` (CZID-285).
  class FedWorkflowRunsWorkflowVersionType < Types::BaseObject
    graphql_name "query_fedWorkflowRuns_items_workflowVersion"

    field :version, String, null: true, camelize: false
    field :workflow, Types::FedWorkflowRunsWorkflowVersionWorkflowType, null: true, camelize: false
  end
end
