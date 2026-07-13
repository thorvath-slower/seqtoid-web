module Types
  # Federation mesh type `query_fedWorkflowRuns_items_entityInputs_edges_items_node`
  # (CZID-285): a sequencing_read entity input pointing at the run's sample id.
  class FedWorkflowRunsEntityInputsNodeType < Types::BaseObject
    graphql_name "query_fedWorkflowRuns_items_entityInputs_edges_items_node"

    field :inputEntityId, String, null: true, camelize: false
    field :entityType, String, null: true, camelize: false
  end
end
