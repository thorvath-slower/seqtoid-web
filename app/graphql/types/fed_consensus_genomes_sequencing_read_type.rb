module Types
  # Federation mesh type `query_fedConsensusGenomes_items_sequencingRead` (CZID-285).
  # Only `id` is ever populated (the discovery branch) or selected, so the deeper
  # sample subtree the mesh declares is intentionally omitted -- neither frontend
  # consumer of fedConsensusGenomes selects beyond sequencingRead.id.
  class FedConsensusGenomesSequencingReadType < Types::BaseObject
    graphql_name "query_fedConsensusGenomes_items_sequencingRead"

    field :id, String, null: true, camelize: false
  end
end
