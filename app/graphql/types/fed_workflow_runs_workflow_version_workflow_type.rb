module Types
  # Federation mesh type `query_fedWorkflowRuns_items_workflowVersion_workflow`
  # (CZID-285). `name` carries the run's creation_source (TODO upstream: the FE is
  # meant to move to rawInputsJson).
  class FedWorkflowRunsWorkflowVersionWorkflowType < Types::BaseObject
    graphql_name "query_fedWorkflowRuns_items_workflowVersion_workflow"

    field :name, String, null: true, camelize: false
  end
end
