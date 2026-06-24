module Types
  # Federation mesh type `query_fedWorkflowRuns_items_entityInputs` (CZID-285): the
  # synthetic entity-inputs connection the federation built around the run's sample.
  class FedWorkflowRunsEntityInputsType < Types::BaseObject
    graphql_name "query_fedWorkflowRuns_items_entityInputs"

    field :edges, [Types::FedWorkflowRunsEntityInputsEdgeType], null: false, camelize: false
  end
end
