module Types
  # Federation mesh type `query_fedWorkflowRuns_items_entityInputs_edges_items`
  # (CZID-285).
  class FedWorkflowRunsEntityInputsEdgeType < Types::BaseObject
    graphql_name "query_fedWorkflowRuns_items_entityInputs_edges_items"

    field :node, Types::FedWorkflowRunsEntityInputsNodeType, null: false, camelize: false
  end
end
