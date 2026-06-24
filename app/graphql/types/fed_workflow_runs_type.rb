module Types
  # Federation mesh type `query_fedWorkflowRuns_items` (CZID-285): one discovery-view
  # workflow run, mapped from the /workflow_runs.json (mode: basic) serialization.
  class FedWorkflowRunsType < Types::BaseObject
    graphql_name "query_fedWorkflowRuns_items"

    field :id, String, null: false, camelize: false
    field :ownerUserId, Int, null: false, camelize: false
    field :startedAt, String, null: true, camelize: false
    field :status, String, null: true, camelize: false
    field :errorLabel, String, null: true, camelize: false
    field :rawInputsJson, String, null: true, camelize: false
    field :workflowVersion, Types::FedWorkflowRunsWorkflowVersionType, null: true, camelize: false
    field :entityInputs, Types::FedWorkflowRunsEntityInputsType, null: false, camelize: false
  end
end
