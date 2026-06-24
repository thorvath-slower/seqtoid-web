module Types
  # Federation mesh type `query_fedConsensusGenomes_items_accession` (CZID-285).
  class FedConsensusGenomesAccessionType < Types::BaseObject
    graphql_name "query_fedConsensusGenomes_items_accession"

    field :accessionId, String, null: true, camelize: false
    field :accessionName, String, null: true, camelize: false
  end
end
