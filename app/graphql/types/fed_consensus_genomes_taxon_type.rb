module Types
  # Federation mesh type `query_fedConsensusGenomes_items_taxon` (CZID-285).
  class FedConsensusGenomesTaxonType < Types::BaseObject
    graphql_name "query_fedConsensusGenomes_items_taxon"

    field :name, String, null: true, camelize: false
    field :id, String, null: true, camelize: false
    field :commonName, String, null: true, camelize: false
  end
end
